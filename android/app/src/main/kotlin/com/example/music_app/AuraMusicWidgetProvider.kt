package com.example.music_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import java.io.File

class AuraMusicWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, AuraMusicWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_aura_material_you)

            // Read state saved by Flutter HomeWidgetService
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val title = prefs.getString("flutter.track_title", null) 
                ?: prefs.getString("track_title", "Aura Music") ?: "Aura Music"
            val artist = prefs.getString("flutter.track_artist", null) 
                ?: prefs.getString("track_artist", "Tap to play music") ?: "Tap to play music"
            val isPlaying = prefs.getBoolean("flutter.is_playing", false) 
                || prefs.getBoolean("is_playing", false)
            val artPath = prefs.getString("flutter.track_art_path", null) 
                ?: prefs.getString("track_art_path", null)

            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_artist, artist)
            views.setTextViewText(
                R.id.widget_status,
                if (isPlaying) "Playing" else "Paused"
            )

            // Dynamic Play / Pause Icon
            views.setImageViewResource(
                R.id.widget_btn_play_pause,
                if (isPlaying) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
            )

            // Try loading cached album art if available
            if (!artPath.isNullOrBlank()) {
                try {
                    val artFile = File(artPath)
                    if (artFile.exists() && artFile.canRead()) {
                        val bitmap = BitmapFactory.decodeFile(artFile.absolutePath)
                        if (bitmap != null) {
                            views.setImageViewBitmap(R.id.widget_album_art, bitmap)
                        } else {
                            views.setImageViewResource(R.id.widget_album_art, R.mipmap.ic_launcher)
                        }
                    } else {
                        views.setImageViewResource(R.id.widget_album_art, R.mipmap.ic_launcher)
                    }
                } catch (_: Exception) {
                    views.setImageViewResource(R.id.widget_album_art, R.mipmap.ic_launcher)
                }
            } else {
                views.setImageViewResource(R.id.widget_album_art, R.mipmap.ic_launcher)
            }

            // PendingIntent 1: Open app on widget body click
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("aura://now-playing")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openAppPendingIntent = PendingIntent.getActivity(
                context,
                0,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent)

            // PendingIntent 2: Play / Pause toggle via MediaButtonReceiver
            val playPausePendingIntent = createMediaButtonPendingIntent(
                context,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
                101
            )
            views.setOnClickPendingIntent(R.id.widget_btn_play_pause, playPausePendingIntent)

            // PendingIntent 3: Previous track
            val prevPendingIntent = createMediaButtonPendingIntent(
                context,
                KeyEvent.KEYCODE_MEDIA_PREVIOUS,
                102
            )
            views.setOnClickPendingIntent(R.id.widget_btn_prev, prevPendingIntent)

            // PendingIntent 4: Next track
            val nextPendingIntent = createMediaButtonPendingIntent(
                context,
                KeyEvent.KEYCODE_MEDIA_NEXT,
                103
            )
            views.setOnClickPendingIntent(R.id.widget_btn_next, nextPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun createMediaButtonPendingIntent(
            context: Context,
            keyCode: Int,
            requestCode: Int
        ): PendingIntent {
            val keyEvent = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                setComponent(ComponentName(context, MediaButtonReceiver::class.java))
                putExtra(Intent.EXTRA_KEY_EVENT, keyEvent)
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}
