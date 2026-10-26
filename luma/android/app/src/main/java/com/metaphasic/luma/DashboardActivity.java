package com.metaphasic.luma;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebView;

/** Local preview of the icon grid. No network permission is declared. */
public class DashboardActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WebView web = new WebView(this);
        web.getSettings().setJavaScriptEnabled(false);
        web.loadUrl("file:///android_asset/dashboard/index.html");
        setContentView(web);
    }
}
