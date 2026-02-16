# Secure Communication Protocol Plan (Challenge-Response + AES-GCM)

This document outlines the plan to upgrade the Monkeycraft WebSocket protocol from plaintext to an encrypted, mutually authenticated channel using a Challenge-Response mechanism and AES-GCM encryption.

## 1. Protocol Flow

### Phase 1: Handshake & Mutual Authentication
1.  **Connection Established**: Client connects to `ws://IP:PORT`.
2.  **Server Hello**:
    *   Server generates a random 16-byte `server_salt`.
    *   Server sends:
        ```json
        {
          "type": "HELLO",
          "salt": "<Base64 encoded server_salt>"
        }
        ```
3.  **Client Auth**:
    *   Client generates a random 16-byte `client_salt`.
    *   Client derives `SessionKey` (see Section 2).
    *   Client computes `ClientSignature = HMAC-SHA256(SessionKey, server_salt)`.
    *   Client sends:
        ```json
        {
          "type": "AUTH",
          "salt": "<Base64 encoded client_salt>",
          "signature": "<Base64 encoded ClientSignature>"
        }
        ```
4.  **Server Verification & Ack**:
    *   Server derives `SessionKey` using the received `client_salt`.
    *   Server verifies `ClientSignature`. If invalid, close connection.
    *   Server computes `ServerSignature = HMAC-SHA256(SessionKey, client_salt)`.
    *   Server sends:
        ```json
        {
          "type": "AUTH_OK",
          "signature": "<Base64 encoded ServerSignature>"
        }
        ```
    *   Client verifies `ServerSignature`. If invalid, close connection.

### Phase 2: Encrypted Communication
After `AUTH_OK`, all subsequent messages (Commands, Events, Video Frames) are wrapped in an encrypted envelope.

*   **Wrapper Message**:
    ```json
    {
      "type": "SECURE",
      "iv": "<Base64 encoded unique IV (12 bytes)>",
      "payload": "<Base64 encoded AES-GCM ciphertext>"
    }
    ```
*   **Payload**: The plaintext JSON string of the original message (e.g., `{"type": "RUN_COMMAND", ...}`).

## 2. Cryptographic Specifications

*   **Password**: The existing generated password (Base58 string).
*   **Key Derivation (PBKDF2)**:
    *   Algorithm: `PBKDF2WithHmacSHA256`
    *   Password: `The User Password`
    *   Salt: `server_salt` (bytes) + `client_salt` (bytes)
    *   Iterations: `10000` (Balance between security and mobile performance)
    *   Key Length: `256 bits` (32 bytes)
*   **Encryption (AES-GCM)**:
    *   Algorithm: `AES/GCM/NoPadding`
    *   Key: The derived `SessionKey`.
    *   IV: Random 12 bytes per message (Must be unique).
    *   Tag Length: 128 bits (Authentication Tag).

## 3. Implementation Plan

### Java Server Side (Minecraft Mod)
1.  **Dependencies**: Use standard `javax.crypto` (Java 8+ supports AES-GCM).
2.  **CryptoUtils Class**: Create a helper for:
    *   PBKDF2 Key Derivation.
    *   AES-GCM Encryption/Decryption.
    *   HMAC-SHA256 generation.
3.  **WebSocketServerHandler Updates**:
    *   Modify `onOpen` to send `HELLO`.
    *   Add state `isEncrypted` to the WebSocket session.
    *   Modify `onMessage` to handle `AUTH` and `SECURE` types.
    *   Implement handshake verification logic.
    *   Update `broadcastFrame` and `sendSystemMessage` to encrypt outgoing data if session is authenticated.

### Flutter Client Side (Mobile App)
1.  **Dependencies**: Add `cryptography` package (or `encrypt`) for PBKDF2 and AES-GCM.
2.  **Protocol Handler**:
    *   Intercept the initial connection flow.
    *   Handle `HELLO` -> Generate Salt -> Derive Key -> Send `AUTH`.
    *   Wait for `AUTH_OK`.
3.  **Message Wrapping**:
    *   Create an interceptor/wrapper that encrypts outgoing JSON before sending.
    *   Decrypt incoming `SECURE` messages before passing them to the app logic.

## 4. Security Guarantees
*   **Mutual Auth**: Both sides prove knowledge of the password without sending it.
*   **Confidentiality**: AES-GCM ensures MITM cannot read commands or video stream.
*   **Integrity**: AES-GCM ensures MITM cannot tamper with messages.
*   **Replay Protection**: Unique IVs and GCM integrity prevent replay of old encrypted messages (mostly).

## 5. Next Steps
1.  Implement `CryptoUtils` in Java.
2.  Update Java `WebSocketServerHandler`.
3.  Verify with a test client script or unit test.
4.  (User to implement Flutter side based on this spec).
