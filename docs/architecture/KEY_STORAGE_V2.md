# Protected key storage and revocation v2

Kristin stores private signing and credential material only in an OS-native credential broker or an external protected store. Repository files, application settings, logs, prompts and evidence contain opaque provider references, public keys, purposes, trust domains and status only.

The platform mapping is Windows Credential Manager, macOS Keychain and Linux Secret Service, with an external HSM/provider option. A missing provider fails closed. Revocation is immediate at resolution time; cached handles do not override revoked status.
