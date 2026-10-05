# Milestone 4 gate: steps for the owner

The spec's gate: **a clean run through onboarding in a fresh macOS user account**, and **the permission revocation test passes**. Both need your hands; together they take about 15 minutes, most of it waiting for the model download in the new account.

## A. Onboarding in a fresh account (~10 minutes)

1. **Create a test account:** System Settings › Users & Groups › Add User. Make it a Standard user named something like "Murmur Test". This asks for your password.
2. **Switch to it:** menu bar › Control Center › your name › Murmur Test (or log out and in). In the new account, open **/Applications/Murmur.app**.
3. **Go through setup.** Grant the three permissions when asked, choosing Quit & Reopen if macOS offers it. Let the models download (~3 GB) and do the practice dictations. At the end the Murmur window opens on Home. Then dictate once into TextEdit with Fn.

Note anything that confused you, didn't work, or needed a step the window didn't explain. Afterwards switch back to your own account; you can delete the test account later.

## B. Permission revocation (~3 minutes, in your own account)

1. With Murmur running, open System Settings › Privacy & Security › **Accessibility** and turn **Murmur off**. Within about 2 seconds the Flow Bar should say Murmur lost the Accessibility permission. Dictate into Notes: nothing should be pasted, the text should be on the clipboard (⌘V pastes it), and it should be in Murmur's History.
2. Turn Murmur **back on**. Dictate again: it pastes, and the notice is gone.
3. Repeat with **Input Monitoring**: turned off, Fn stops starting dictations and the notice appears. Turned back on, it works again; if not, Murmur › Settings › General shows what to do (at worst, quit and reopen Murmur).

Tell Claude the results (or just "A passed, B passed"), plus anything odd.
