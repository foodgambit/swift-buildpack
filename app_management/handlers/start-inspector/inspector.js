/* IBM SDK for Node.js Buildpack
* Copyright 2014 the original author or authors.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*      http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/
/*eslint-env node*/
var nodePath = require("path"),
    nodeUrl = require("url"),
    nodeUtil = require("util");
var InspectorDebugServer = require("node-inspector/lib/debug-server").DebugServer,
    Config = require("node-inspector/lib/config"),
    URLRewriter = require("../../utils/url-rewriter");

/**
 * Override node-inspector's DebugServer. The goal here is to allow NI to pretend it's running
 * at the website root `/` when in reality it's prefixed by the proxy path `bluemix-debug/inspector`.
 * The strategy has 2 parts:
 *
 *  1) Strip proxy path off incoming request URLs, so as not to confuse NI middleware.
 *  2) Inject the proxy path into any client-facing URLs, so that the client browser
 *     issues the correct requests. This is primarily a concern for Websocket connections
 *     and certain redirects.
 */
function CustomDebugServer(options) {
    options = options || {};
    this.prefix = options.prefix;
    InspectorDebugServer.apply(this, arguments);
}
nodeUtil.inherits(CustomDebugServer, InspectorDebugServer);

// e.g. https://{route}/bluemix-debug/inspector/debug?ws={route}/bluemix-debug/inspector&port={debugPort}
CustomDebugServer.prototype._getClientURL = function(req2) {
    var headers = req2.headers;
    return nodeUrl.format({
        protocol: headers["x-forwarded-proto"] || req2.protocol,
        host: headers.host,
        pathname: "/" + this.prefix + "/", //"/debug",
        search: "?ws=" + headers.host + "/" + this.prefix + "&port=" + this._config.debugPort
    });
};

// e.g. wss://{route}/bluemix-debug/inspector?port={debugPort}
CustomDebugServer.prototype._getWebsocketURL = function(req2) {
    var headers = req2.headers,
        protocol = headers["x-forwarded-proto"] || req2.protocol;
    return nodeUrl.format({
        protocol: protocol === "https" ? "wss://" : "ws://",
        host: headers.host,
        pathname: "/" + this.prefix,
        search: "?port=" + this._config.debugPort
    });
};

/* @override Node-inspector calls _getUrlFromReq(req) to obtain the redirect sent to the client
 * when they access the root inspector URL. So this simply returns the client facing URL.
 */
CustomDebugServer.prototype._getUrlFromReq = CustomDebugServer.prototype._getClientURL;

/* @override Rewrite incoming request URLs to remove the proxy path prefix before they
 * reach NI middleware.
 */
CustomDebugServer.prototype.start = function() {
    InspectorDebugServer.prototype.start.apply(this, arguments);

    // Add a rewrite rule for the parent path of `this.prefix`. This is needed to handle
    // requests to /bluemix-debug/protocol.json which the Node Inspector UI unfortunately
    // relies on.
    var parentPrefix = nodePath.resolve("/" + this.prefix, "../")
    var prefixes = ["/" + this.prefix, parentPrefix];

    // We do this both for the websocket server...
    new URLRewriter(prefixes).attach(this.wsServer);

    // ...and HTTP server
    var rewriter = new URLRewriter(prefixes).attach(this._httpServer);

    // A bit tricky: wait until the first request comes in, so we have the IncomingRequest
    // context needed by _getClientURL() and _getWebSocketURL(). At that point, we
    // override the address() and wsAddress() functions from the parent class.
    rewriter.postRewrite = function(req) {
        if (this._patched) {
            return;
        }
        this._patched = true;

        /* @override Returns the client-facing URL, so it must account for the proxy path.
         */
        this.address = function() {
            var address = this._httpServer.address();
            address.url = this._getClientURL(req);
            return address;
        };
        /* @override Similar to #address() but for the websocket URL.
         */
        this.wsAddress = function() {
            var address = this._httpServer.address();
            address.url = this._getWebsocketURL(req);
            return address;
        };
    }.bind(this);
};

module.exports = function(options) {
    var webPort = options.webPort,
        debugPort = options.debugPort,
        prefix = options.prefix;

    if (!webPort || !debugPort || !options.prefix) {
        throw new Error("Missing param");
    }

    var debugServer = new CustomDebugServer({
        prefix: prefix,
    });
    var config = new Config([]);
    config.webPort = webPort;
    config.debugPort = debugPort;
    debugServer.start(config);

    return debugServer;
};
