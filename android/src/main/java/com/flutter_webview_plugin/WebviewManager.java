package com.flutter_webview_plugin;

import android.content.Intent;
import android.net.Uri;
import android.annotation.TargetApi;
import android.app.Activity;
import android.os.Build;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.*;
import android.widget.FrameLayout;

import com.flutter_webview_plugin.BrowserChromeClient;
import com.flutter_webview_plugin.BrowserClient;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import static android.app.Activity.RESULT_OK;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Created by lejard_h on 20/12/2017.
 */

class WebviewManager {

    private ValueCallback<Uri> mUploadMessage;
    private ValueCallback<Uri[]> mUploadMessageArray;
    private final static int FILECHOOSER_RESULTCODE=1;
    private final FlutterWebviewConfigurator configurator;

    @TargetApi(7)
    class ResultHandler {
        public boolean handleResult(int requestCode, int resultCode, Intent intent){
            boolean handled = false;
            if(Build.VERSION.SDK_INT >= 21){
                Uri[] results = null;
                // check result
                if(resultCode == Activity.RESULT_OK){
                    if(requestCode == FILECHOOSER_RESULTCODE){
                        if(mUploadMessageArray != null){
                            String dataString = intent.getDataString();
                            if(dataString != null){
                                results = new Uri[]{Uri.parse(dataString)};
                            }
                        }
                        handled = true;
                    }
                }
                mUploadMessageArray.onReceiveValue(results);
                mUploadMessageArray = null;
            }else {
                if (requestCode == FILECHOOSER_RESULTCODE) {
                    if (null != mUploadMessage) {
                        Uri result = intent == null || resultCode != RESULT_OK ? null
                                : intent.getData();
                        mUploadMessage.onReceiveValue(result);
                        mUploadMessage = null;
                    }
                    handled = true;
                }
            }
            return handled;
        }
    }

    boolean closed = false;
    WebView webView;
    Activity activity;
    ResultHandler resultHandler;
    String token;

    WebviewManager(Activity activity, FlutterWebviewConfigurator configurator, List<String> interceptUrls) {
        this.webView = new WebView(activity);
        this.activity = activity;
        this.resultHandler = new ResultHandler();
        this.configurator = configurator;
        WebViewClient webViewClient = new BrowserClient(interceptUrls);
        WebChromeClient webChromeClient = new BrowserChromeClient(activity);
        webView.setOnKeyListener(new View.OnKeyListener() {
            @Override
            public boolean onKey(View v, int keyCode, KeyEvent event) {
                if (event.getAction() == KeyEvent.ACTION_DOWN) {
                    switch (keyCode) {
                        case KeyEvent.KEYCODE_BACK:
                            if (webView.canGoBack()) {
                                webView.goBack();
                                webGoBack();
                            } else {
                                close();
                            }
                            return true;
                    }
                }

                return false;
            }
        });
        ((ObservableWebView) webView).setOnScrollChangedCallback(new ObservableWebView.OnScrollChangedCallback(){
            public void onScroll(int x, int y, int oldx, int oldy){
                Map<String, Object> yDirection = new HashMap<>();
                yDirection.put("yDirection", (double)y);
                FlutterWebviewPlugin.channel.invokeMethod("onScrollYChanged", yDirection);
                Map<String, Object> xDirection = new HashMap<>();
                xDirection.put("xDirection", (double)x);
                FlutterWebviewPlugin.channel.invokeMethod("onScrollXChanged", xDirection);
            }
        });

        webView.setWebViewClient(webViewClient);
        webView.setWebChromeClient(webChromeClient);
    }

    private void clearCookies() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            CookieManager.getInstance().removeAllCookies(new ValueCallback<Boolean>() {
                @Override
                public void onReceiveValue(Boolean aBoolean) {

                }
            });
        } else {
            CookieManager.getInstance().removeAllCookie();
        }
    }

    private void clearCache() {
        webView.clearCache(true);
        webView.clearFormData();
    }

    void openUrl(boolean withJavascript, boolean clearCache, boolean hidden, boolean clearCookies, String userAgent, String url, Map<String, String> headers, boolean withZoom, boolean withLocalStorage, boolean scrollBar) {
        webView.getSettings().setJavaScriptEnabled(withJavascript);
        webView.getSettings().setBuiltInZoomControls(withZoom);
        webView.getSettings().setSupportZoom(withZoom);
        webView.getSettings().setDomStorageEnabled(withLocalStorage);
        webView.getSettings().setUseWideViewPort(true);
        webView.getSettings().setLoadWithOverviewMode(true);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            webView.getSettings().setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        }
        webView.getSettings().setJavaScriptCanOpenWindowsAutomatically(true);
        token = additionalHttpHeaders.get("hexindai-token");
        webView.addJavascriptInterface(new JavaScriptinterface(token), "App");
        if (clearCache) {
            clearCache();
        }

        if (hidden) {
            webView.setVisibility(View.INVISIBLE);
        }

        if (clearCookies) {
            clearCookies();
        }

        if (userAgent != null) {
            webView.getSettings().setUserAgentString(userAgent);
        }
      
        if(!scrollBar){
            webView.setVerticalScrollBarEnabled(false);
        }

        if (headers != null) {
            webView.loadUrl(url, headers);
        } else {
            webView.loadUrl(url);
        }
    }

    void close(boolean goBack, MethodChannel.Result result) {
        if (goBack && webView.canGoBack()) {
            webView.goBack();
            webGoBack();
        } else {
            if (webView != null) {
                ViewGroup vg = (ViewGroup) (webView.getParent());
                vg.removeView(webView);
            }
            webView = null;
            if (result != null) {
                result.success(null);
            }
            closed = true;
            FlutterWebviewPlugin.channel.invokeMethod("onDestroy", null);
        }
    }

    void close() {
        close(false, null);
    }

    @TargetApi(Build.VERSION_CODES.KITKAT)
    void eval(MethodCall call, final MethodChannel.Result result) {
        String code = call.argument("code");

        webView.evaluateJavascript(code, new ValueCallback<String>() {
            @Override
            public void onReceiveValue(String value) {
                result.success(value);
            }
        });
    }
    /** 
    * Reloads the Webview.
    */
    void reload(MethodCall call, MethodChannel.Result result) {
        if (webView != null) {
            webView.reload();
        }
    }
    /** 
    * Navigates back on the Webview.
    */
    void back(MethodCall call, MethodChannel.Result result) {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        }
    }
    /** 
    * Navigates forward on the Webview.
    */
    void forward(MethodCall call, MethodChannel.Result result) {
        if (webView != null && webView.canGoForward()) {
            webView.goForward();
        }
    }

    void resize(FrameLayout.LayoutParams params) {
        webView.setLayoutParams(params);
    }
    /** 
    * Checks if going back on the Webview is possible.
    */
    boolean canGoBack() {
        return webView.canGoBack();
    }
    /** 
    * Checks if going forward on the Webview is possible.
    */
    boolean canGoForward() {
        return webView.canGoForward();
    }
    void hide(MethodCall call, MethodChannel.Result result) {
        if (webView != null) {
            webView.setVisibility(View.INVISIBLE);
        }
    }
    void show(MethodCall call, MethodChannel.Result result) {
        if (webView != null) {
            webView.setVisibility(View.VISIBLE);
        }
    }

    void stopLoading(MethodCall call, MethodChannel.Result result){
        if (webView != null){
            webView.stopLoading();
        }
    }

    void webGoBack() {
        FlutterWebviewPlugin.channel.invokeMethod("onWebGoBack", null);
    }

    public class JavaScriptinterface {
        String token;

        private JavaScriptinterface(String token) {
            this.token = token;
        }

        @JavascriptInterface
        public String getToken() {
            return token;
        }
    }

}
