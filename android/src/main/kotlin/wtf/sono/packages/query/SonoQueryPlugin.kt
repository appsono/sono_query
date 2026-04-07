package wtf.sono.packages.query

import android.content.Context
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SonoQueryPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "sono_query")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSongsWithMetadata" -> {
                val args = call.arguments as? Map<*, *>
                val minDurationMs = (args?.get("minDurationMs") as? Number)?.toLong()
                val excludedPaths = (args?.get("excludedPaths") as? List<*>)
                    ?.filterIsInstance<String>() ?: emptyList()
                result.success(getSongsWithMetadata(minDurationMs, excludedPaths))
            }
            "getCoverFromMediaStore" -> {
                val filePath = call.arguments as String
                result.success(getCoverFromMediaStore(filePath))
            }
            else -> result.notImplemented()
        }
    }

    /// Returns all metadata from MediaStore in one query
    /// On API 30+: genre is included directly (AudioColumns.GENRE)
    /// On API < 30: genre is resolved from Genres join tables
    ///
    /// [minDurationMs] > skip songs shorter than this, defaults to > 0
    /// [excludedPaths] > skip songs whose path starts with any of these prefixes
    private fun getSongsWithMetadata(
        minDurationMs: Long?,
        excludedPaths: List<String>
    ): List<Map<String, Any?>> {
        val songs = mutableListOf<Map<String, Any?>>()
        val hasGenreColumn = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

        val genreLookup = mutableMapOf<String, String>()
        if (!hasGenreColumn) {
            context.contentResolver.query(
                MediaStore.Audio.Genres.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Audio.Genres._ID, MediaStore.Audio.Genres.NAME),
                null, null, null
            )?.use { genreCursor ->
                val idIdx = genreCursor.getColumnIndexOrThrow(MediaStore.Audio.Genres._ID)
                val nameIdx = genreCursor.getColumnIndexOrThrow(MediaStore.Audio.Genres.NAME)

                while (genreCursor.moveToNext()) {
                    val genreName = fixMojibake(genreCursor.getString(nameIdx)) ?: continue
                    val memberUri = MediaStore.Audio.Genres.Members.getContentUri(
                        "external", genreCursor.getLong(idIdx)
                    )

                    context.contentResolver.query(
                        memberUri,
                        arrayOf(MediaStore.Audio.Media.DATA),
                        null, null, null
                    )?.use { memberCursor ->
                        val dataIdx = memberCursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                        while (memberCursor.moveToNext()) {
                            memberCursor.getString(dataIdx)?.let { genreLookup[it] = genreName }
                        }
                    }
                }
            }
        }

        val baseProjection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.YEAR,
        )

        val projection = if (hasGenreColumn) {
            baseProjection + MediaStore.Audio.Media.GENRE
        } else {
            baseProjection
        }

        //build WHERE clause: min duration + path exclusions
        val durationThreshold = minDurationMs ?: 0L
        val selectionParts = mutableListOf("${MediaStore.Audio.Media.DURATION} > $durationThreshold")
        val selectionArgs = mutableListOf<String>()

        for (path in excludedPaths) {
            selectionParts.add("${MediaStore.Audio.Media.DATA} NOT LIKE ?")
            //append /% so /storage/emulated/0/Ringtones matches everything inside
            selectionArgs.add("${path.trimEnd('/')}/%")
        }

        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selectionParts.joinToString(" AND "),
            selectionArgs.toTypedArray(),
            null
        )?.use {cursor ->
            val dataIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val titleIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val yearIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
            val genreIdx = if (hasGenreColumn) cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.GENRE) else -1

            while (cursor.moveToNext()) {
                val path = cursor.getString(dataIdx)
                val artist = fixMojibake(cursor.getString(artistIdx))
                val album = fixMojibake(cursor.getString(albumIdx))

                songs.add(mapOf(
                    "path" to path,
                    "title" to fixMojibake(cursor.getString(titleIdx)),
                    //MediaStore return <unknown> for missing artist/album
                    "artist" to if (artist == "<unknown>") null else artist,
                    "album" to if (album == "<unknown>") null else album,
                    "duration" to cursor.getLong(durationIdx), //ms
                    "year" to cursor.getInt(yearIdx).let { if (it == 0) null else it },
                    "genre" to if (genreIdx >= 0) fixMojibake(cursor.getString(genreIdx)) else genreLookup[path],
                ))
            }
        }

        return songs
    }

    private fun getCoverFromMediaStore(filePath: String): ByteArray? {
        val projection = arrayOf(MediaStore.Audio.Media._ID)
        val selection = "${MediaStore.Audio.Media.DATA} = ?"
        val selectionArgs = arrayOf(filePath)

        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID))
                val uri = android.content.ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                )
                try {
                    val bitmap = context.contentResolver.loadThumbnail(uri, android.util.Size(512, 512), null)
                    val stream = java.io.ByteArrayOutputStream()
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, stream)
                    return stream.toByteArray()
                } catch (e: Exception) {
                    return null
                }
            }
        }
        return null
    }
}

/// Fixes UTF-8 mojibake: some ID3 taggers store UTF-8 bytes but declare
/// Latin-1/CP1252. MediaStore reads the declared encoding, producing garbled
/// text (e.g. "Donâ€™t" instead of "Don't").
/// Re-encodes as Windows-1252 bytes then decodes as UTF-8.
private fun fixMojibake(input: String?): String? {
    if (input == null) return null
    //quick check: if no bytes > 0x7F, nothing to fix
    if (input.all { it.code <= 0x7F }) return input
    return try {
        val cp1252 = Charsets.ISO_8859_1 //close enough for detection
        val bytes = input.toByteArray(cp1252)
        val decoded = String(bytes, Charsets.UTF_8)
        //reject if decoding produced replacement chars
        if (decoded.contains('\uFFFD')) input else decoded
    } catch (_: Exception) {
        input
    }
}
