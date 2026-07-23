package wtf.sono.packages.query

import android.app.Activity
import android.app.PendingIntent
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class SonoQueryPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    // background pool for scans / cover decode / file copies
    // created in onAttachedToEngine, torn down in onDetachedFromEngine
    private var executor: ExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

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
        executor = Executors.newFixedThreadPool(2)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor?.shutdown()
        executor = null
    }

    // MethodChannel results must be delivered on platform main thread.
    // Heavy work (MediaStore scans, bitmap decode/encode, file copies) runs
    // on [executor]; only result delivery hops back to main
    private fun runInBackground(
        result: MethodChannel.Result,
        task: () -> Any?,
    ) {
        val exec = executor
        if (exec == null) {
            result.error("DETACHED", "plugin detached from engine", null)
            return
        }
        exec.execute {
            try {
                val value = task()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("NATIVE_ERROR", e.message, null) }
            }
        }
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
                runInBackground(result) { getSongsWithMetadata(minDurationMs, excludedPaths) }
            }

            "getCoverFromMediaStore" -> {
                val filePath = call.arguments as String
                runInBackground(result) { getCoverFromMediaStore(filePath) }
            }

            "getCoverThumbnail" -> {
                val args = call.arguments as? Map<*, *>
                val path = args?.get("path") as? String
                val maxDim = (args?.get("maxDim") as? Number)?.toInt() ?: 512
                if (path == null) {
                    result.error("BAD_ARGS", "path required", null)
                } else {
                    runInBackground(result) {
                        getCoverFromMediaStore(path, maxDim)
                            ?: getEmbeddedThumbnail(path, maxDim)
                    }
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
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("BAD_ARGS", "path required", null)
                } else {
                    runInBackground(result) { mediaStoreUriFor(path)?.toString() }
                }
            }

            "resolveMediaStoreIds" -> {
                val ids = call.argument<List<*>>("ids")
                    ?.mapNotNull { (it as? Number)?.toLong() } ?: emptyList()
                runInBackground(result) {
                    resolveByColumn(MediaStore.Audio.Media._ID, ids, null)
                }
            }

            "resolveMediaStoreAlbumIds" -> {
                val ids = call.argument<List<*>>("albumIds")
                    ?.mapNotNull { (it as? Number)?.toLong() } ?: emptyList()
                runInBackground(result) {
                    // song order makes representative stable across runs
                    resolveByColumn(
                        MediaStore.Audio.Media.ALBUM_ID,
                        ids,
                        "${MediaStore.Audio.Media.TRACK} ASC"
                    )
                }
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
    private fun getCoverFromMediaStore(
        filePath: String,
        maxDim: Int = 512,
    ): ByteArray? {
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
                        return try {
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.JPEG, 90, stream)
                            stream.toByteArray()
                        } finally {
                            // explicit recycle helps GC pressure on older devices
                            bitmap.recycle()
                        }
                    } catch (e: Exception) {
                        return null
                    }
                }
            }
        return null
    }

    private val passThroughBytes = 300 * 1024

    private fun getEmbeddedThumbnail(
        path: String,
        maxDim: Int,
    ): ByteArray? {
        val mmr = MediaMetadataRetriever()
        return try {
            mmr.setDataSource(path)
            val pic = mmr.embeddedPicture ?: return null
            decodeSubsampled(pic, maxDim)
        } catch (_: Exception) {
            null
        } finally {
            try {
                mmr.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun decodeSubsampled(
        bytes: ByteArray,
        maxDim: Int,
    ): ByteArray? {
        // pass 1: bounds only, no pixel allocation
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val w = bounds.outWidth
        val h = bounds.outHeight
        if (w <= 0 || h <= 0) return null

        if (w <= maxDim && h <= maxDim && bytes.size <= passThroughBytes) {
            return bytes
        }

        // pass 2: largest power-of-two subsample that keeps result >= maxDim
        var sample = 1
        while (w / (sample * 2) >= maxDim || h / (sample * 2) >= maxDim) {
            sample *= 2
        }
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap =
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts) ?: return null
        return try {
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            out.toByteArray()
        } finally {
            bitmap.recycle()
        }
    }

    // ==== legacy id resolution ====

    private val idChunkSize = 900

    // Maps values of [keyColumn] to a file path, for ids old Sono
    // stored before it knew about paths
    //
    // First row per key wins, so [sortOrder] decides which song
    // represents an album. Unresolvable ids are simply absent
    private fun resolveByColumn(
        keyColumn: String,
        ids: List<Long>,
        sortOrder: String?,
    ): Map<Long, String> {
        if (ids.isEmpty()) return emptyMap()

        val out = HashMap<Long, String>(ids.size)
        val projection = arrayOf(keyColumn, MediaStore.Audio.Media.DATA)

        for (chunk in ids.distinct().chunked(idChunkSize)) {
            val selection = "$keyColumn IN (${chunk.joinToString(",") { "?" }})"
            val args = chunk.map { it.toString() }.toTypedArray()

            context.contentResolver
                .query(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    projection,
                    selection,
                    args,
                    sortOrder,
                )?.use { cursor ->
                    val keyIdx = cursor.getColumnIndexOrThrow(keyColumn)
                    val dataIdx =
                        cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                    while (cursor.moveToNext()) {
                        val key = cursor.getLong(keyIdx)
                        if (out.containsKey(key)) continue
                        val path = cursor.getString(dataIdx) ?: continue
                        out[key] = path
                    }
                }
        }
        return out
    }

    // ==== write plumbing ====

    // copies original files bytes into app-private cache dir
    // returns cache files absolute path
    private fun copyToAppCache(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("BAD_ARGS", "path required", null)
            return
        }
        val exec = executor
        if (exec == null) {
            result.error("DETACHED", "plugin detached from engine", null)
            return
        }

        val basename = File(path).name
        val cacheFile = File(context.cacheDir, "edit_${UUID.randomUUID()}_$basename")

        exec.execute {
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
                        mainHandler.post {
                            result.error(
                                "NOT_FOUND",
                                "file not readable and not in MediaStore: $path",
                                null,
                            )
                        }
                        return@execute
                    }
                    context.contentResolver.openInputStream(uri).use { input ->
                        if (input == null) {
                            mainHandler.post {
                                result.error("OPEN_FAILED", "could not open input stream", null)
                            }
                            return@execute
                        }
                        FileOutputStream(cacheFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                }
                mainHandler.post { result.success(cacheFile.absolutePath) }
            } catch (e: Exception) {
                // clean up partial cache on failure
                cacheFile.delete()
                mainHandler.post { result.error("COPY_FAILED", e.message, null) }
            }
        }
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
        val exec = executor
        if (exec == null) {
            result.error("DETACHED", "plugin detached from engine", null)
            return
        }

        // file IO + MediaStore lookup off the main thread; only the
        // system permission dialog (API 30+) hops back to main
        exec.execute {
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
                    mainHandler.post { result.success(true) }
                    return@execute
                } catch (_: SecurityException) {
                    // fall through to MediaStore path
                } catch (e: Exception) {
                    mainHandler.post { result.error("WRITE_FAILED", e.message, null) }
                    return@execute
                }
            }

            // MediaStore path
            val uri = mediaStoreUriFor(originalPath)
            if (uri == null) {
                mainHandler.post {
                    result.error("NOT_FOUND", "not in MediaStore: $originalPath", null)
                }
                return@execute
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                // dialog launch needs the main thread + activity
                mainHandler.post { requestAndWriteApi30(uri, cachePath, originalPath, result) }
            } else {
                // pre-Android 11: try direct ContentResolver write, no per-file dialog
                tryDirectContentResolverWrite(uri, cachePath, originalPath, result)
            }
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
        // (off the main thread; onActivityResult itself returns immediately)
        val exec = executor
        if (exec == null) {
            result.error("DETACHED", "plugin detached from engine", null)
            return true
        }
        exec.execute {
            try {
                context.contentResolver.openOutputStream(uri, "wt").use { output ->
                    if (output == null) {
                        mainHandler.post {
                            result.error("OPEN_FAILED", "could not open output stream", null)
                        }
                        return@execute
                    }
                    FileInputStream(File(cachePath)).use { input ->
                        input.copyTo(output)
                    }
                }
                scanFile(originalPath)
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("WRITE_FAILED", e.message, null) }
            }
        }
        return true
    }

    // runs on background pool; results hop back to main
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
                    mainHandler.post {
                        result.error("OPEN_FAILED", "could not open output stream", null)
                    }
                    return
                }
                FileInputStream(File(cachePath)).use { input ->
                    input.copyTo(output)
                }
            }
            scanFile(originalPath)
            mainHandler.post { result.success(true) }
        } catch (e: Exception) {
            mainHandler.post { result.error("WRITE_FAILED", e.message, null) }
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
