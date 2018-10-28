package com.flutter_webview_plugin;

import android.graphics.Bitmap;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebResourceError;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Created by lejard_h on 20/12/2017.
 */

public class BrowserClient extends WebViewClient {

    private final List<String> mInterceptUrls;

    public BrowserClient(List<String> interceptUrls) {
        super();
        mInterceptUrls = interceptUrls;
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
        super.onPageStarted(view, url, favicon);
        Map<String, Object> data = new HashMap<>();
        data.put("url", url);
        data.put("type", "startLoad");
        FlutterWebviewPlugin.channel.invokeMethod("onState", data);
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, String url) {
        Map<String, Object> data = new HashMap<>();
        data.put("url", url);

        FlutterWebviewPlugin.channel.invokeMethod("onUrlChanged", data);
        for (String interceptUrl : mInterceptUrls) {
            if(url.contains(interceptUrl)){
                return true;
            }
        }
        return false;
    }

    @Override
    public void onPageFinished(WebView view, String url) {
        super.onPageFinished(view, url);
        Map<String, Object> data = new HashMap<>();
        data.put("url", url);
        data.put("type", "finishLoad");
        FlutterWebviewPlugin.channel.invokeMethod("onState", data);

    }

    @Override
    public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
        super.onReceivedError(view, errorCode, description, failingUrl);
        FlutterWebviewPlugin.channel.invokeMethod("onWebError", null);
    }

    @Override
    public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
        super.onReceivedHttpError(view, request, errorResponse);
        Map<String, Object> data = new HashMap<>();
        data.put("url", request.getUrl().toString());
        data.put("code", Integer.toString(errorResponse.getStatusCode()));
        FlutterWebviewPlugin.channel.invokeMethod("onHttpError", data);
    }
}