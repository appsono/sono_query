package wtf.sono.packages.query

import android.app.Activity
import android.app.PendingIntent
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID

class SonoQueryPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
 PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // activity reference, set/cleared by ActivityAware callbacks
    // null whenever flutter is detached from an activity (e.g. during config changes)
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    // pending result for system "allow write?" dialog
    // only one in flight at a time, second request rejects with already-in-progress
    private var pendingWriteResult: MethodChannel.Result? = null
    private var pendingCachePath: String? = null
    private var pendingOriginalPath: String? = null
    private var pendingUri: Uri? = null

    companion object {
        private const val WRITE_REQUEST_CODE = 41001
    }

    // ==== FlutterPlugin ====
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "sono_query")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // ==== ActivityAware ====
    // these four callbacks hand us an Activity reference whenever one exists
    // we register/unregister an ActivityResultListener so we can receive the
    // result of the system permission dialog launched by commitFromCache
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activity = null
        activityBinding = null
    }

    // ==== method dispatch ====
    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "getSongsWithMetadata" -> {
                val args = call.arguments as? Map<*, *>
                val minDurationMs = (args?.get("minDurationMs") as? Number)?.toLong()
                val excludedPaths =
                    (args?.get("excludedPaths") as? List<*>)
                        ?.filterIsInstance<String>() ?: emptyList()
                result.success(getSongsWithMetadata(minDurationMs, excludedPaths))
            }

            "getCoverFromMediaStore" -> {
                val filePath = call.arguments as String
                result.success(getCoverFromMediaStore(filePath))
            }

            "getCoverThumbnail" -> {
                val args = call.arguments as? Map<*, *>
                val path = args?.get("path") as? String
                val maxDim = (args?.get("maxDim") as? Number)?.toInt() ?: 512
                if (path == null) {
                    result.error("BAD_ARGS", "path required", null)
                } else {
                    result.success(getCoverFromMediaStore(path, maxDim))
                }
            }

            "rescanFile" -> {
                val filePath = call.arguments as String
                MediaScannerConnection.scanFile(
                    context,
                    arrayOf(filePath),
                    null,
                    null,
                )
                result.success(null)
            }

            "resolveContentUri" -> {
                resolveContentUri(call, result)
            }

            "copyToAppCache" -> {
                copyToAppCache(call, result)
            }

            "commitFromCache" -> {
                commitFromCache(call, result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    // ==== scan / cover / rescan ====

    // Returns all metadata from MediaStore in one query
    // On API 30+: genre is included directly (AudioColumns.GENRE)
    // On API < 30: genre is resolved from Genres join tables
    //
    // [minDurationMs] > skip songs shorter than this, defaults to > 0
    // [excludedPaths] > skip songs whose path starts with any of these prefixes
    private fun getSongsWithMetadata(
        minDurationMs: Long?,
        excludedPaths: List<String>,
    ): List<Map<String, Any?>> {
        val songs = mutableListOf<Map<String, Any?>>()
        val hasGenreColumn = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

        val genreLookup = mutableMapOf<String, String>()
        if (!hasGenreColumn) {
            context.contentResolver
                .query(
                    MediaStore.Audio.Genres.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Audio.Genres._ID, MediaStore.Audio.Genres.NAME),
                    null,
                    null,
                    null,
                )?.use { genreCursor ->
                    val idIdx = genreCursor.getColumnIndexOrThrow(MediaStore.Audio.Genres._ID)
                    val nameIdx = genreCursor.getColumnIndexOrThrow(MediaStore.Audio.Genres.NAME)

                    while (genreCursor.moveToNext()) {
                        val genreName = fixMojibake(genreCursor.getString(nameIdx)) ?: continue
                        val memberUri =
                            MediaStore.Audio.Genres.Members.getContentUri(
                                "external",
                                genreCursor.getLong(idIdx),
                            )

                        context.contentResolver
                            .query(
                                memberUri,
                                arrayOf(MediaStore.Audio.Media.DATA),
                                null,
                                null,
                                null,
                            )?.use { memberCursor ->
                                val dataIdx = memberCursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                                while (memberCursor.moveToNext()) {
                                    memberCursor.getString(dataIdx)?.let { genreLookup[it] = genreName }
                                }
                            }
                    }
                }
        }

        val baseProjection =
            arrayOf(
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.YEAR,
                MediaStore.Audio.Media.TRACK,
                MediaStore.Audio.Media.DATE_MODIFIED,
                MediaStore.Audio.Media.SIZE,
            )

        val projection =
            if (hasGenreColumn) {
                baseProjection + MediaStore.Audio.Media.GENRE
            } else {
                baseProjection
            }

        // build WHERE clause: min duration + path exclusions
        val durationThreshold = minDurationMs ?: 0L
        val selectionParts = mutableListOf("${MediaStore.Audio.Media.DURATION} > $durationThreshold")
        val selectionArgs = mutableListOf<String>()

        for (path in excludedPaths) {
            selectionParts.add("${MediaStore.Audio.Media.DATA} NOT LIKE ?")
            // append /% so /storage/emulated/0/Ringtones matches everything inside
            selectionArgs.add("${path.trimEnd('/')}/%")
        }

        context.contentResolver
            .query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selectionParts.joinToString(" AND "),
                selectionArgs.toTypedArray(),
                null,
            )?.use { cursor ->
                val dataIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val titleIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val durationIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val yearIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
                val trackIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
                val genreIdx = if (hasGenreColumn) cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.GENRE) else -1
                val dateModIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
                val sizeIdx = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)

                while (cursor.moveToNext()) {
                    val path = cursor.getString(dataIdx)
                    val artist = fixMojibake(cursor.getString(artistIdx))
                    val album = fixMojibake(cursor.getString(albumIdx))

                    songs.add(
                        mapOf(
                            "path" to path,
                            "title" to fixMojibake(cursor.getString(titleIdx)),
                            // MediaStore return <unknown> for missing artist/album
                            "artist" to if (artist == "<unknown>") null else artist,
                            "album" to if (album == "<unknown>") null else album,
                            "duration" to cursor.getLong(durationIdx), // ms
                            "year" to cursor.getInt(yearIdx).let { if (it == 0) null else it },
                            "genre" to if (genreIdx >= 0) fixMojibake(cursor.getString(genreIdx)) else genreLookup[path],
                            "track" to cursor.getInt(trackIdx).let { if (it == 0) null else it },
                            // DATE_MODIFIED is seconds since epoch
                            "mtimeMs" to cursor.getLong(dateModIdx) * 1000L,
                            "size" to cursor.getLong(sizeIdx),
                        ),
                    )
                }
            }

        return songs
    }

    // loadThumbnail is API 29+; NoSuchMethodError is an Error and was NOT
    // caught by the catch(Exception) below, so this also fixes a pre-Q crash
    private fun getCoverFromMediaStore(filePath: String, maxDim: Int = 512): ByteArray? {
       if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val projection = arrayOf(MediaStore.Audio.Media._ID)
        val selection = "${MediaStore.Audio.Media.DATA} = ?"
        val selectionArgs = arrayOf(filePath)

        context.contentResolver
            .query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                selectionArgs,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID))
                    val uri =
                        ContentUris.withAppendedId(
                            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                            id,
                        )
                    try {
                        val bitmap =
                            context.contentResolver.loadThumbnail(
                                uri,
                                android.util.Size(maxDim, maxDim),
                                null,
                            )
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

    // ==== write plumbing ====

    // path -> MediaStore content URI string, or null when not indexed
    private fun resolveContentUri(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("BAD_ARGS", "path required", null)
            return
        }
        val uri = mediaStoreUriFor(path)
        result.success(uri?.toString())
    }

    private fun mediaStoreUriFor(path: String): Uri? {
        val collection =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }

        val projection = arrayOf(MediaStore.Audio.Media._ID)
        val selection = "${MediaStore.Audio.Media.DATA} = ?"
        val selectionArgs = arrayOf(path)

        context.contentResolver
            .query(
                collection,
                projection,
                selection,
                selectionArgs,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID))
                    return ContentUris.withAppendedId(collection, id)
                }
            }
        return null
    }

    // copies original files bytes into app-private cache dir
    // returns cache files absolute path. caller is responsible for
    // deleting cache file when done. prefers direct File read when
    // file is in apps own scope, otherwise goes via ContentResolver
    // (which works without permission for read)
    private fun copyToAppCache(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("BAD_ARGS", "path required", null)
            return
        }

        val basename = File(path).name
        val cacheFile = File(context.cacheDir, "edit_${UUID.randomUUID()}_$basename")

        try {
            val directFile = File(path)
            if (directFile.canRead()) {
                FileInputStream(directFile).use { input ->
                    FileOutputStream(cacheFile).use { output ->
                        input.copyTo(output)
                    }
                }
            } else {
                val uri = mediaStoreUriFor(path)
                if (uri == null) {
                    result.error(
                        "NOT_FOUND",
                        "file not readable and not in MediaStore: $path",
                        null,
                    )
                    return
                }
                context.contentResolver.openInputStream(uri).use { input ->
                    if (input == null) {
                        result.error("OPEN_FAILED", "could not open input stream", null)
                        return
                    }
                    FileOutputStream(cacheFile).use { output ->
                        input.copyTo(output)
                    }
                }
            }
            result.success(cacheFile.absolutePath)
        } catch (e: Exception) {
            // clean up partial cache on failure
            cacheFile.delete()
            result.error("COPY_FAILED", e.message, null)
        }
    }

    // writes the cache files bytes back to original path
    // tries direct File write first (works for files in apps own scope);
    // on Android 11+ falls back to MediaStore.createWriteRequest which shows
    // a system "allow Sono to modify this audio file?" dialog
    // on success also notifies MediaScanner so other apps see new tags
    private fun commitFromCache(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val cachePath = call.argument<String>("cachePath")
        val originalPath = call.argument<String>("originalPath")
        if (cachePath == null || originalPath == null) {
            result.error("BAD_ARGS", "cachePath and originalPath required", null)
            return
        }

        // try direct write first, falls through to ContentResolver+dialog on PermissionDenied
        val directFile = File(originalPath)
        if (directFile.canWrite()) {
            try {
                FileInputStream(File(cachePath)).use { input ->
                    FileOutputStream(directFile).use { output ->
                        input.copyTo(output)
                    }
                }
                scanFile(originalPath)
                result.success(true)
                return
            } catch (_: SecurityException) {
                // fall through to MediaStore path
            } catch (e: Exception) {
                result.error("WRITE_FAILED", e.message, null)
                return
            }
        }

        // MediaStore path
        val uri = mediaStoreUriFor(originalPath)
        if (uri == null) {
            result.error("NOT_FOUND", "not in MediaStore: $originalPath", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            requestAndWriteApi30(uri, cachePath, originalPath, result)
        } else {
            // pre-Android 11: try direct ContentResolver write, no per-file dialog
            tryDirectContentResolverWrite(uri, cachePath, originalPath, result)
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun requestAndWriteApi30(
        uri: Uri,
        cachePath: String,
        originalPath: String,
        result: MethodChannel.Result,
    ) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "activity not attached", null)
            return
        }
        if (pendingWriteResult != null) {
            result.error("BUSY", "another write request is in progress", null)
            return
        }

        // pending intent that, when launched, shows system dialog
        val pendingIntent: PendingIntent =
            MediaStore.createWriteRequest(context.contentResolver, listOf(uri))

        // store state so onActivityResult can complete operation later
        pendingWriteResult = result
        pendingCachePath = cachePath
        pendingOriginalPath = originalPath
        pendingUri = uri

        try {
            act.startIntentSenderForResult(
                pendingIntent.intentSender,
                WRITE_REQUEST_CODE,
                null,
                0,
                0,
                0,
            )
        } catch (e: IntentSender.SendIntentException) {
            pendingWriteResult = null
            pendingCachePath = null
            pendingOriginalPath = null
            pendingUri = null
            result.error("INTENT_FAILED", e.message, null)
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != WRITE_REQUEST_CODE) return false

        val result = pendingWriteResult
        val cachePath = pendingCachePath
        val originalPath = pendingOriginalPath
        val uri = pendingUri

        pendingWriteResult = null
        pendingCachePath = null
        pendingOriginalPath = null
        pendingUri = null

        if (result == null || cachePath == null || originalPath == null || uri == null) {
            return true // consumed the result even if state was wrong
        }

        if (resultCode != Activity.RESULT_OK) {
            result.success(false) // user denied
            return true
        }

        // user granted: stream cache file back into original via ContentResolver
        try {
            context.contentResolver.openOutputStream(uri, "wt").use { output ->
                if (output == null) {
                    result.error("OPEN_FAILED", "could not open output stream", null)
                    return true
                }
                FileInputStream(File(cachePath)).use { input ->
                    input.copyTo(output)
                }
            }
            scanFile(originalPath)
            result.success(true)
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message, null)
        }
        return true
    }

    private fun tryDirectContentResolverWrite(
        uri: Uri,
        cachePath: String,
        originalPath: String,
        result: MethodChannel.Result,
    ) {
        try {
            // on API 29 needs requestLegacyExternalStorage=true in app manifest
            // on API 28 and below works with WRITE_EXTERNAL_STORAGE granted
            context.contentResolver.openOutputStream(uri, "wt").use { output ->
                if (output == null) {
                    result.error("OPEN_FAILED", "could not open output stream", null)
                    return
                }
                FileInputStream(File(cachePath)).use { input ->
                    input.copyTo(output)
                }
            }
            scanFile(originalPath)
            result.success(true)
        } catch (e: Exception) {
            result.error("WRITE_FAILED", e.message, null)
        }
    }

    private fun scanFile(path: String) {
        try {
            MediaScannerConnection.scanFile(context, arrayOf(path), null, null)
        } catch (_: Exception) {
            // best-effort, do not fail whole operation
        }
    }
}

// Fixes UTF-8 mojibake: some ID3 taggers store UTF-8 bytes but declare
// Latin-1/CP1252. MediaStore reads the declared encoding, producing garbled
// text (e.g. "Donâ€™t" instead of "Don't").
// Re-encodes as Windows-1252 bytes then decodes as UTF-8.
private fun fixMojibake(input: String?): String? {
    if (input == null) return null
    return try {
        val cp1252 = charset("windows-1252")
        val bytes = input.toByteArray(cp1252)
        val decoded = String(bytes, Charsets.UTF_8)
        // mojibake always expands: multi-byte UTF-8 sequences become multiple
        // single-byte CP1252 chars, so a valid fix will always be shorter
        if (!decoded.contains('\uFFFD') && decoded.length < input.length) decoded else input
    } catch (_: Exception) {
        input
    }
}
