package wtf.sono.packages.query

import android.content.Context
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
            "getAudioFilePaths" -> result.success(getAudioFilePaths())
            "getCoverFromMediaStore" -> {
                val filePath = call.arguments as String
                result.success(getCoverFromMediaStore(filePath))
            }
            else -> result.notImplemented()
        }
    }

    private fun getAudioFilePaths():  List<String> {
        val paths = mutableListOf<String>()
        val projection = arrayOf(MediaStore.Audio.Media.DATA)

        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            null,
            null,
            null
        )?.use  { cursor ->
            val dataIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            while (cursor.moveToNext()) {
                paths.add(cursor.getString(dataIndex))
            }
        }

        return paths
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
