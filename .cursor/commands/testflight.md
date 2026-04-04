# Testflight (Myprelura)

When the user runs `/testflight` for **this repo** (`Myprelura/`), follow these steps:

1. **Build, export, upload (same pattern as Prelura Swift)**  
   From the **Myprelura** project root:

   ```bash
   ./scripts/build-ipa-for-testflight.sh --upload
   ```

   This archives, exports the IPA, checks push entitlements, then uploads via `altool`.

2. **Credentials** (checked in order)  
   - `scripts/testflight-credentials.json` (gitignored; copy from `scripts/testflight-credentials.json.example`)  
   - Keychain `AC_PASSWORD` for account **`Myprelura`**  
   - Keychain `AC_PASSWORD` for account **`Prelura-swift`** (same Apple team — works if you only ever set up Prelura Swift)

3. **Monitoring**  
   Watch the script output until upload finishes. Log file: `/tmp/testflight_upload_myprelura.log`  
   Confirm success or paste errors (signing, validation, auth).

4. **Report**  
   Note TestFlight processing in App Store Connect; mention Delivery UUID if printed.

If credentials are missing, user can run `./scripts/setup-testflight-keychain.sh` in **this** repo, or reuse Prelura Swift keychain setup.
