package com.nexgenled.command

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register the shortcut manager plugin for dynamic shortcuts
        flutterEngine.plugins.add(ShortcutManagerPlugin())
    }
}
