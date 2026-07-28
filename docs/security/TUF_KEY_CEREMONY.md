# TUF root-key ceremony and compromise recovery

## Initial ceremony

- Prepare three offline root keys on separate owner-controlled devices.
- Record public keys and roles only; never copy private material into the repository.
- Require two-of-three signatures for root metadata.
- Verify role thresholds, expiries, consistent snapshots and delegated channels on an offline validation machine.
- Publish the signed root only after independent checksum comparison.

## Root rotation

Create a new root version signed by both the old threshold and the new threshold. Clients must update sequentially and reject skipped, rolled-back or expired root versions.

## Online-role compromise

Revoke the affected targets, snapshot or timestamp key, rotate it from protected storage, publish fresh metadata and use emergency delegation only for bounded recovery. A compromised online key cannot replace the offline root.

## Lost-threshold recovery

Stop publication. Restore from independently held offline root keys and the last verified metadata backup. If the root threshold cannot be satisfied, the existing trust domain cannot be silently replaced; owner-approved reinstall/rebootstrap is required.
