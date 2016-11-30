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
/*eslint no-process-exit:0*/
var log = require("../../utils/log"),
    inspector = require("./inspector");
var prefix,
    port,
    debugPort;

// Get arguments
(function() {
    var args = process.argv.slice(2);
    prefix = args[0];
    port = parseInt(args[1], 10);
    debugPort = parseInt(args[2], 10);

    if (!port || !prefix) {
        log.error("Usage: " + process.argv.slice(0, 2).join(" ") + " [PREFIX] [PORT] [DEBUG_PORT]");
        process.exit(1);
    }
}());

// Create & start the server
var debugServer = inspector({
    webPort: port,
    debugPort: debugPort,
    prefix: prefix
});

debugServer.on("error", onError);
debugServer.on("listening", onListening);
debugServer.on("close", function () {
    log.error("Debugged process has exited. Inspector exiting...");
    process.exit();
});

function onError(err) {
    log.error("Cannot start the inspector. Error: %s.", err.message || err);
    if (err.code === "EADDRINUSE") {
        log.error("There is another process already listening on the port: %s", port);
    }
}

function onListening() {
    log.log("node-inspector is active. Visit the web page to start debugging.");
}
