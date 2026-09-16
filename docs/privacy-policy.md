# Cascade Privacy Policy

_Last updated: September 16, 2026_

Cascade ("the app") is an iOS app that turns sheet music into interactive falling-note piano lessons and videos. This policy explains what information the app handles and why.

## Summary

- Cascade works offline for everything except sheet-music scanning.
- Scanning sends the page images you choose to our scan service so an AI model can read the notation. Pages are processed and discarded. They are not used to train models.
- Signing in with Apple gives us only an anonymous account identifier. We never receive your name or email address.
- We do not run ads, we do not track you across apps or websites, and we do not sell data.

## Information stored on your device

The following stays on your device and is never sent to us:

- Your song library (MusicXML files you import or scan, and their titles)
- Practice statistics, streaks, achievements, and settings
- Videos you export (until you share or delete them)

Deleting the app deletes all of it.

## Information sent to our servers

### Sheet-music scanning

When you tap **Convert to Falling Notes**, the images of the pages you selected are uploaded over an encrypted (HTTPS) connection to the Cascade scan service, which runs on Cloudflare Workers. The service forwards the images to a third-party AI model provider (Anthropic, and Google as a fallback) to transcribe the notation into MusicXML, then returns the result to your device.

- Page images are held in memory only for the duration of the request and are not written to storage.
- A hash (fingerprint) of the images and the resulting transcription may be cached for up to 60 days so that re-scanning identical pages is instant and does not consume a free scan. The cache contains no images and cannot be reversed into them.
- AI providers process the images under their API terms, which prohibit using API inputs to train their models.

### Sign in with Apple

To meter free scans, the app asks you to sign in with Apple. We request no name and no email address. Apple gives us a stable, anonymous identifier that is unique to Cascade. Alongside it we store only:

- how many scans you have used
- the date the record was created

That is the entire account.

### Scan packs (in-app purchases)

Additional scans are sold as consumable in-app purchases through Apple. Apple handles payment; we never see your payment details. To add the credits to your account, the app sends us Apple's signed record of the purchase, and we store the transaction identifier, the product purchased, and the credit balance alongside your anonymous account. This is used only to grant credits once and to prevent the same purchase being redeemed twice.

### Deleting your account

Open **Scan Sheet Music → gear icon → Delete Account**. This removes your usage record and credit balance from our servers immediately and signs you out. Unused purchased credits are forfeited. Songs in your library remain on your device.

## Permissions the app asks for

- **Camera** — to photograph sheet music. Used only while the scanner is open.
- **Photo library (add only)** — to save exported videos when you choose "Save Video" in the share sheet.
- **Notifications** — optional daily practice reminders, scheduled locally on your device.

## Children

Cascade does not knowingly collect personal information from children. The only account data we hold is an anonymous identifier and a scan counter.

## Changes

If this policy changes, the updated version will be posted at this address with a new date.

## Contact

Questions about privacy: jasonandjenn511@gmail.com
