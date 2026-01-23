package com.nexgenled.command

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter plugin for managing Android App Shortcuts.
 *
 * Supports:
 * - Dynamic shortcuts (up to 4) for user scenes
 * - Pinned shortcuts on home screen
 * - Shortcut usage reporting
 */
class ShortcutManagerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.nexgen.lumina/shortcuts")
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) {
            // Shortcuts API requires Android 7.1+
            when (call.method) {
                "isPinnedShortcutSupported" -> result.success(false)
                else -> result.success(true) // Silently succeed for other methods
            }
            return
        }

        when (call.method) {
            "updateDynamicShortcuts" -> updateDynamicShortcuts(call, result)
            "pinShortcut" -> pinShortcut(call, result)
            "reportShortcutUsed" -> reportShortcutUsed(call, result)
            "removeShortcut" -> removeShortcut(call, result)
            "isPinnedShortcutSupported" -> isPinnedShortcutSupported(result)
            "removeAllDynamicShortcuts" -> removeAllDynamicShortcuts(result)
            else -> result.notImplemented()
        }
    }

    @RequiresApi(Build.VERSION_CODES.N_MR1)
    private fun updateDynamicShortcuts(call: MethodCall, result: MethodChannel.Result) {
        try {
            val shortcutsData = call.argument<List<Map<String, Any>>>("shortcuts")
            if (shortcutsData == null) {
                result.error("INVALID_ARGS", "Missing shortcuts argument", null)
                return
            }

            val shortcutManager = context.getSystemService(ShortcutManager::class.java)
            val maxShortcuts = shortcutManager.maxShortcutCountPerActivity

            val shortcutInfos = shortcutsData.take(maxShortcuts.coerceAtMost(4)).mapNotNull { data ->
                createShortcutInfo(data)
            }

            shortcutManager.dynamicShortcuts = shortcutInfos
            result.success(true)
        } catch (e: Exception) {
            result.error("UPDATE_FAILED", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.N_MR1)
    private fun pinShortcut(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                result.success(false)
                return
            }

            val id = call.argument<String>("id")
            val shortLabel = call.argument<String>("shortLabel")
            val uri = call.argument<String>("uri")

            if (id == null || shortLabel == null || uri == null) {
                result.error("INVALID_ARGS", "Missing required arguments", null)
                return
            }

            val shortcutManager = context.getSystemService(ShortcutManager::class.java)

            if (!shortcutManager.isRequestPinShortcutSupported) {
                result.success(false)
                return
            }

            val shortcutInfo = ShortcutInfo.Builder(context, id)
                .setShortLabel(shortLabel)
                .setLongLabel(call.argument<String>("longLabel") ?: shortLabel)
                .setIcon(getIconForType(call.argument<String>("iconType") ?: "custom"))
                .setIntent(Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
                .build()

            val success = shortcutManager.requestPinShortcut(shortcutInfo, null)
            result.success(success)
        } catch (e: Exception) {
            result.error("PIN_FAILED", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.N_MR1)
    private fun reportShortcutUsed(call: MethodCall, result: MethodChannel.Result) {
        try {
            val id = call.argument<String>("id")
            if (id == null) {
                result.error("INVALID_ARGS", "Missing id argument", null)
                return
            }

            val shortcutManager = context.getSystemService(ShortcutManager::class.java)
            shortcutManager.reportShortcutUsed(id)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    @RequiresApi(Build.VERSION_CODES.N_MR1)
    private fun removeShortcut(call: MethodCall, result: MethodChannel.Result) {
        try {
            val id = call.argument<String>("id")
            if (id == null) {
                result.error("INVALID_ARGS", "Missing id argument", null)
                return
            }

            val shortcutManager = context.getSystemService(ShortcutManager::class.java)
            shortcutManager.removeDynamicShortcuts(listOf(id))
            result.success(true)
        } catch (e: Exception) {
            result.error("REMOVE_FAILED", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.N_MR1)
    private fun removeAllDynamicShortcuts(result: MethodChannel.Result) {
        try {
            val shortcutManager = context.getSystemService(ShortcutManager::class.java)
            shortcutManager.removeAllDynamicShortcuts()
            result.success(true)
        } catch (e: Exception) {
            result.error("REMOVE_ALL_FAILED", e.message, null)
        }
    }

    private fun isPinnedShortcutSupported(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }

        try {
            val shortcutManager = context.getSystemService(ShortcutManager::class.java)
            result.success(shortcutManager.isRequestPinShortcutSupported)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    @RequiresApi(Build.VERSION_CODES.N_MR1)
    private fun createShortcutInfo(data: Map<String, Any>): ShortcutInfo? {
        val id = data["id"] as? String ?: return null
        val shortLabel = data["shortLabel"] as? String ?: return null
        val uri = data["uri"] as? String ?: return null

        val longLabel = data["longLabel"] as? String ?: shortLabel
        val iconType = data["iconType"] as? String ?: "custom"

        return ShortcutInfo.Builder(context, id)
            .setShortLabel(shortLabel)
            .setLongLabel(longLabel)
            .setIcon(getIconForType(iconType))
            .setIntent(Intent(Intent.ACTION_VIEW, Uri.parse(uri)))
            .build()
    }

    @RequiresApi(Build.VERSION_CODES.N_MR1)
    private fun getIconForType(iconType: String): Icon {
        val iconRes = when (iconType) {
            "pattern" -> android.R.drawable.ic_menu_gallery
            "camera", "snapshot" -> android.R.drawable.ic_menu_camera
            "system" -> android.R.drawable.ic_menu_preferences
            else -> android.R.drawable.ic_menu_compass
        }
        return Icon.createWithResource(context, iconRes)
    }
}
