// web/serial_interops.js
// Provides Web Serial API access to Flutter via dart:js_interop.
// Loaded by index.html BEFORE flutter_bootstrap.js boots.
// Exposes window.serialBridge for Dart @JS bindings to call.

(function () {
  'use strict';

  let port = null;
  let reader = null;
  let writer = null;
  let lineBuffer = '';
  const lineListeners = [];

  window.serialBridge = {

    isAvailable: () => !!(navigator && navigator.serial),

    // Opens browser port picker with NO filters — shows ALL serial ports.
    // Filtering by VID/PID is unreliable because ESP32 boards use many
    // different USB-to-serial chips (CP2102, CH340, CH9102, native USB, FTDI).
    // The empty filters array is the Web Serial spec way to show everything.
    requestPort: async () => {
      try {
        // No filters = show all available serial ports
        port = await navigator.serial.requestPort();
        return true;
      } catch (e) {
        // User cancelled the picker — not an error
        if (e.name === 'NotFoundError' || e.name === 'AbortError') {
          console.info('Serial port picker cancelled by user');
        } else {
          console.warn('Serial requestPort error:', e);
        }
        return false;
      }
    },

    // Opens the selected port. Tries 115200 first; falls back gracefully.
    openPort: async (baudRate) => {
      if (!port) throw new Error('No port selected — call requestPort first');
      try {
        await port.open({ baudRate: baudRate || 115200 });
      } catch (e) {
        // Port may already be open (e.g. Arduino IDE left it open)
        if (e.name === 'InvalidStateError') {
          console.warn('Port already open, proceeding');
        } else {
          throw e;
        }
      }
      writer = port.writable.getWriter();
      _startReading(); // fire-and-forget background read loop
    },

    // Writes a UTF-8 string to the serial port.
    write: async (text) => {
      if (!writer) throw new Error('Port not open');
      const encoded = new TextEncoder().encode(text);
      await writer.write(encoded);
    },

    // Registers a callback(line: string) for each complete \n-terminated line.
    addLineListener: (cb) => {
      if (typeof cb === 'function' && !lineListeners.includes(cb)) {
        lineListeners.push(cb);
      }
    },

    removeLineListener: (cb) => {
      const i = lineListeners.indexOf(cb);
      if (i >= 0) lineListeners.splice(i, 1);
    },

    // Closes reader, writer, and port cleanly.
    close: async () => {
      try {
        if (reader) {
          await reader.cancel();
          reader.releaseLock();
          reader = null;
        }
      } catch (e) {
        console.warn('Error cancelling reader:', e);
      }
      try {
        if (writer) {
          await writer.close();
          writer = null;
        }
      } catch (e) {
        console.warn('Error closing writer:', e);
      }
      try {
        if (port) {
          await port.close();
          port = null;
        }
      } catch (e) {
        console.warn('Error closing port:', e);
      }
      lineBuffer = '';
    },
  };

  // Background read loop — splits incoming bytes on newlines and fires listeners.
  async function _startReading() {
    if (!port || !port.readable) return;
    const decoder = new TextDecoder();
    reader = port.readable.getReader();
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        lineBuffer += decoder.decode(value, { stream: true });
        let nl;
        while ((nl = lineBuffer.indexOf('\n')) !== -1) {
          const line = lineBuffer.slice(0, nl).replace(/\r$/, '');
          lineBuffer = lineBuffer.slice(nl + 1);
          if (line.length > 0) {
            lineListeners.forEach(cb => {
              try { cb(line); } catch (e) {
                console.error('lineListener threw:', e);
              }
            });
          }
        }
      }
    } catch (e) {
      // NetworkError is expected when port.close() cancels the read
      if (e.name !== 'NetworkError') {
        console.warn('Serial read loop ended:', e.name, e.message);
      }
    } finally {
      try { reader.releaseLock(); } catch (_) {}
      reader = null;
    }
  }

})();
