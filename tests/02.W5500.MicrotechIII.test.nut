// Copyright (c) 2017 Electric Imp
// This file is licensed under the MIT License
// http://opensource.org/licenses/MIT

// echo server address and port
const SOURCE_IP = "192.168.1.185";
const SUBNET_MASK = "255.255.255.0";
const ROUTER = "192.168.1.1";
const MTIII_SERVER_IP = "192.168.1.42";
const MTIII_SERVER_PORT = 4242;
const MTIII_CONNECT_ATTEMPTS = 5;
const MTIII_RESPONSE_TIMEOUT = 2; // seconds

MTIII_SEQUENCE <- [
    // Init
    "\x0e\x00\x04\x00\xd8\x6c\x81\x00\x16\x00\x00\x00\x00\x00", // Request
    "\x12\x00\x04\x00\xd8\x6c\x81\x40\x16\x00\x00\x00\x00\x00\x01\x00\x00\x04", // Response

    // Read the serial number
    "\x1a\x00\x0c\x00\xd8\x6c\x24\x00\x16\x00\x00\x00\x00\x00\x04\x23\x89\xd1\xea\x5c\x00\x00\x00\x00\x00\x00", // Request
    128, // Response length

    // Read the config code 1-15
    "\x1a\x00\x0c\x00\xd8\x6c\x24\x00\x16\x00\x00\x00\x00\x00\x0d\x23\x15\x06\xaf\xf0\x00\x00\x00\x00\x00\x00", // Request
    128, // Response length

    // Read the config code 16-30
    "\x1a\x00\x0c\x00\xd8\x6c\x24\x00\x16\x00\x00\x00\x00\x00\x0d\x23\x89\xda\xaf\xf0\x00\x00\x00\x00\x00\x00", // Request
    128, // Response length

    // Fake an error, should timeout
    "timeout", // Request
    null // Response

];

class W5500_MicrotechIII_TestCase extends ImpTestCase {

    wiz = null;
    dhcp = null;
    resetPin = hardware.pinXA;
    interruptPin = hardware.pinXC;
    spiSpeed = 1000;
    spi = hardware.spi0;


    // setup function needed to run others. Instantiates the wiznet driver.
    function setUp() {
        spi.configure(CLOCK_IDLE_LOW | MSB_FIRST | USE_CS_L, spiSpeed);
        wiz = W5500(interruptPin, spi, null, resetPin);
        wiz.configureNetworkSettings(SOURCE_IP, SUBNET_MASK, ROUTER);
        wiz.setNumberOfAvailableSockets(2);
        this.info("Configured IP address to " + SOURCE_IP);
    }


    // Tests the ability of the wiznet to open and close multiple times cleanly
    // Failure to cleanly close the connection leads to the MTIII rejecting new connections
    function _testConnectMultipleTimes() {
        return Promise(function(resolve, reject) {

            local connectOnce;
            connectOnce = function(attempt = 1) {
                wiz.onReady(function() {
                    wiz.openConnection(MTIII_SERVER_IP, MTIII_SERVER_PORT, function(err, connection) {

                        if (err) return reject(format("Connection attempt %d failed to %s:%d: %s", attempt, MTIII_SERVER_IP, MTIII_SERVER_PORT, err.tostring()));
                        this.info(format("Connection attempt %d successful", attempt));

                        // Now disconnect and recurse
                        connection.close(function() {
                            if (attempt >= MTIII_CONNECT_ATTEMPTS) {
                                return resolve(format("Connected to %s:%d a total of %d times", MTIII_SERVER_IP, MTIII_SERVER_PORT, MTIII_CONNECT_ATTEMPTS));
                            } else {
                                connectOnce(attempt + 1);
                            }
                        }.bindenv(this));

                    }.bindenv(this));

                }.bindenv(this));
            }

            // Start connecting sequence
            connectOnce();

        }.bindenv(this));
    }


    // Tests the Wiznet's ability to send and receive binary data to the MTIII
    function testBinaryData() {
        return Promise(function(resolve, reject) {

            wiz.onReady(function() {
                wiz.openConnection(MTIII_SERVER_IP, MTIII_SERVER_PORT, function(err, connection) {

                    if (err) return reject(format("Connection to MTIII failed: %s", err.tostring()));
                    this.info(format("Connection successful"));

                    // Local function for sending and waiting for response
                    local sendAndReceive = function(send, receive, done) {

                        // Transmit the packet to the microtech
                        connection.transmit(send, function(err) {
                            if (err) return done(err, send, null);
                            this.info("Transmitted: " + send.len() + " bytes");
                        }.bindenv(this));

                        // Wait for a response from the microtech
                        connection.receive(function(err, data) {
                            if (err) return done(err, send, null);
                            this.info("Received: " + data.len() + " bytes");
                            done(err, send, data);
                        }.bindenv(this), MTIII_RESPONSE_TIMEOUT);

                    }

                    // Track where we are up to in the sequence
                    local pos = 0;
                    local runSequence;
                    runSequence = function(done) {
                        local send = MTIII_SEQUENCE[pos];
                        local receive = MTIII_SEQUENCE[pos+1];
                        sendAndReceive(send, receive, function(err, sent, received) {

                            // Check the errors
                            if (sent == "timeout" && err != "timeout") {
                                return done("Expected timeout error");
                            } else if (sent != "timeout" && err != null) {
                                return done(err);
                            }

                            // Check the values
                            if (receive == null || (typeof receive == "integer" && received.len() == receive) || received.tostring() == receive.tostring()) {
                                // Continue
                            } else {
                                return done("Response didn't match");
                            }

                            // Move onto the next one
                            pos += 2;
                            if (pos < MTIII_SEQUENCE.len()) {
                                imp.wakeup(0, function() {
                                    runSequence(done);
                                }.bindenv(this));
                            } else {
                                done(null);
                            }
                        }.bindenv(this));
                    }

                    // Start running the sequence
                    runSequence(function(err) {
                        connection.close();
                        if (err) reject(err);
                        else resolve();
                    }.bindenv(this));

                }.bindenv(this));

            }.bindenv(this));

        }.bindenv(this));

    }
}
