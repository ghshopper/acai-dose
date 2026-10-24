package com.acaidose.staff;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Color;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.content.SharedPreferences;
import android.media.Ringtone;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Keeps listening for website orders while the app is in the background or closed.
 * A "New" order sounds the alarm on a loop until a worker accepts it (also while the app is open);
 * a customer tapping "I'm here" gives one alert. Notifications only show when the app is not on screen.
 */
public class OrderWatchService extends Service {

    static final String HOST = "order.acaiee.com";
    static final String PREFS = "watch";
    static final String CH_RUN = "watch";
    static final String CH_ALERT = "orders_v1";
    static final int ID_RUN = 1, ID_ALERT = 2, ID_ARRIVED = 3;
    static final String ACTION_STOP = "com.acaidose.staff.STOP";

    /** Set by MainActivity: true while the app is on screen. */
    static volatile boolean appVisible = false;

    private ScheduledExecutorService loop;
    private MediaPlayer player;
    private PowerManager.WakeLock wake;
    private final Set<Integer> arrivedSeen = new HashSet<>();
    private boolean firstPoll = true;

    /** Saves the login cookie the Flutter side got; empty = logged out. */
    static void saveCookie(Context c, String cookie) {
        c.getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("cookie", cookie == null ? "" : cookie).apply();
    }
    static String cookie(Context c) {
        return c.getSharedPreferences(PREFS, MODE_PRIVATE).getString("cookie", "");
    }
    /** Which shop this device is signed in to: "" for Açaí Dose, "/karak" for Karak Dose. */
    static void saveShop(Context c, String base, String title) {
        c.getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString("base", base == null ? "" : base).putString("title", title == null ? "" : title).apply();
    }
    static String base(Context c) { return c.getSharedPreferences(PREFS, MODE_PRIVATE).getString("base", ""); }
    static String title(Context c) {
        String t = c.getSharedPreferences(PREFS, MODE_PRIVATE).getString("title", "");
        return t.isEmpty() ? "Açaí Dose" : t;
    }

    static void start(Context c) {
        if (cookie(c).isEmpty()) return;
        Intent i = new Intent(c, OrderWatchService.class);
        try {
            if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i); else c.startService(i);
        } catch (Exception ignored) { }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        makeChannels();
        Notification n = base(CH_RUN)
                .setContentTitle(title(this))
                .setContentText("Listening for new orders")
                .setOngoing(true)
                .addAction(new Notification.Action.Builder(null, "Stop", stopIntent()).build())
                .build();
        if (Build.VERSION.SDK_INT >= 34) startForeground(ID_RUN, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        else startForeground(ID_RUN, n);

        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "acaidose:watch");
        wake.acquire();

        loop = Executors.newSingleThreadScheduledExecutor();
        loop.scheduleWithFixedDelay(this::poll, 2, 5, TimeUnit.SECONDS);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) { stopSelf(); return START_NOT_STICKY; }
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (loop != null) loop.shutdownNow();
        stopAlarm();
        if (wake != null && wake.isHeld()) wake.release();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) { return null; }

    // ---------- polling ----------

    private void poll() {
        try {
            String cookie = cookie(this);
            if (cookie.isEmpty()) { stopAlarm(); stopSelf(); return; }
            HttpURLConnection c = (HttpURLConnection) new URL("https://" + HOST + base(this) + "/api/api.php?a=active_orders").openConnection();
            c.setConnectTimeout(8000); c.setReadTimeout(8000);
            c.setRequestProperty("Cookie", cookie);
            c.setRequestProperty("User-Agent", "AcaiDoseApp/1.0 watcher");
            if (c.getResponseCode() != 200) { c.disconnect(); stopAlarm(); return; }   // logged out
            String body = read(c.getInputStream()); c.disconnect();
            JSONArray list = new JSONArray(body);

            int newCount = 0; String firstRef = null, firstCar = null;
            Set<Integer> arrivedNow = new HashSet<>(); String arrivedCar = null;
            for (int i = 0; i < list.length(); i++) {
                JSONObject o = list.getJSONObject(i);
                if ("new".equals(o.optString("status"))) {
                    newCount++;
                    if (firstRef == null) { firstRef = o.optString("ref"); firstCar = o.optString("car_plate"); }
                }
                if (!o.isNull("arrived_at") && !o.optString("arrived_at").isEmpty()) {
                    int id = o.optInt("id");
                    arrivedNow.add(id);
                    if (!arrivedSeen.contains(id) && !firstPoll) arrivedCar = o.optString("car_plate");
                }
            }
            arrivedSeen.clear(); arrivedSeen.addAll(arrivedNow);
            firstPoll = false;

            NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
            if (newCount > 0) {
                startAlarm();
            } else {
                stopAlarm();
            }
            if (newCount > 0 && !appVisible) {
                String title = newCount == 1 ? "New order #" + firstRef : newCount + " new orders";
                String text = (firstCar != null && !firstCar.isEmpty() ? "Car " + firstCar + " · " : "") + "Open the app and press Accept";
                nm.notify(ID_ALERT, base(CH_ALERT).setContentTitle(title).setContentText(text)
                        .setCategory(Notification.CATEGORY_ALARM).setOngoing(true).setOnlyAlertOnce(true)
                        .setFullScreenIntent(openIntent(), true).build());
            } else {
                nm.cancel(ID_ALERT);
            }
            if (arrivedCar != null) {
                if (!appVisible) nm.notify(ID_ARRIVED, base(CH_ALERT).setContentTitle("Customer is here")
                        .setContentText(arrivedCar.isEmpty() ? "A customer has arrived" : "Car " + arrivedCar + " has arrived")
                        .setAutoCancel(true).build());
                beep();
                buzz();
            }
        } catch (Exception e) {
            // No connection: keep trying on the next round.
        }
    }

    private static String read(InputStream in) throws Exception {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buf = new byte[8192]; int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
        in.close();
        return out.toString("UTF-8");
    }

    // ---------- sound ----------

    private synchronized void startAlarm() {
        if (player != null) return;
        try {
            Uri u = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
            if (u == null) u = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            player = new MediaPlayer();
            player.setAudioAttributes(new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
            player.setDataSource(this, u);
            player.setLooping(true);
            player.prepare();
            player.start();
        } catch (Exception e) {
            player = null;
        }
        buzz();
    }

    private synchronized void stopAlarm() {
        if (player == null) return;
        try { player.stop(); } catch (Exception ignored) { }
        player.release();
        player = null;
    }

    private void beep() {
        try {
            Uri u = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            Ringtone r = RingtoneManager.getRingtone(this, u);
            if (r != null) r.play();
        } catch (Exception ignored) { }
    }

    private void buzz() {
        Vibrator v = (Vibrator) getSystemService(VIBRATOR_SERVICE);
        if (v == null || !v.hasVibrator()) return;
        long[] p = {0, 400, 200, 400};
        if (Build.VERSION.SDK_INT >= 26) v.vibrate(VibrationEffect.createWaveform(p, -1)); else v.vibrate(p, -1);
    }

    // ---------- notifications ----------

    private void makeChannels() {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        NotificationChannel run = new NotificationChannel(CH_RUN, "Listening for orders", NotificationManager.IMPORTANCE_MIN);
        run.setShowBadge(false);
        nm.createNotificationChannel(run);
        NotificationChannel alert = new NotificationChannel(CH_ALERT, "New orders", NotificationManager.IMPORTANCE_HIGH);
        alert.setSound(null, null);   // the looping alarm plays the sound itself
        alert.enableLights(true); alert.setLightColor(Color.parseColor("#E39A2E"));
        alert.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        nm.createNotificationChannel(alert);
    }

    @SuppressWarnings("deprecation")
    private Notification.Builder base(String channel) {
        Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, channel) : new Notification.Builder(this);
        if (Build.VERSION.SDK_INT < 26) b.setPriority(CH_ALERT.equals(channel) ? Notification.PRIORITY_MAX : Notification.PRIORITY_MIN);
        return b.setSmallIcon(R.drawable.ic_stat_order).setColor(Color.parseColor("#470D43"))
                .setContentIntent(openIntent()).setVisibility(Notification.VISIBILITY_PUBLIC);
    }

    private PendingIntent openIntent() {
        Intent i = new Intent(this, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        return PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private PendingIntent stopIntent() {
        Intent i = new Intent(this, OrderWatchService.class).setAction(ACTION_STOP);
        return PendingIntent.getService(this, 1, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
}
