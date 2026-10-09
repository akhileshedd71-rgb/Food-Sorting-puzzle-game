# Chef Coins — local economy, version 0.2

Chef Coins are the game's single currency. They are earned and spent locally in this build. Players can see planned coin packs, but their purchase buttons are disabled and no real-money payment or advertising provider is connected.

## Earn and spend

| Action | Chef Coins | Availability |
| --- | ---: | --- |
| Welcome gift | +100 | Once per local profile, including a profile upgraded from 0.1 |
| First campaign clear | +30 | Once per campaign level; replay does not repeat the reward |
| Cooking School graduation | +30 | Once after the third lesson; repeating school does not repeat the gift |
| Verified hint | −10 | Only when a complete winning continuation has been verified |
| Extra tray | −40 | At most one per level attempt; total trays cannot exceed eight |
| Sage enamel finish | −120 | Permanent cosmetic unlock |
| Berry enamel finish | −180 | Permanent cosmetic unlock |
| Classic blue finish, equipping owned finishes | 0 | Always available |
| Undo, restart, campaign replay, tutorial guidance | 0 | Unlimited |

The shop previews 250, 700 and 1,600-coin packs as **Coming later**. They have no fake checkout, real-money price, simulated successful purchase, or development grant button in the player interface. These amounts and the earned prices above are initial tuning choices, not a measured or balanced live economy.

All 150 campaign boards have no-tool solution certificates. A player can clear the complete campaign without spending coins. If the wallet is empty, the game offers free undo/restart. There are no energy costs, forced ads, randomized paid rewards or mandatory coin gates.

## Spending integrity

`EconomyService` owns spending; UI buttons request actions and display results. Confirmation occurs before a paid tool or finish is applied. A failed or unavailable hint, canceled confirmation or unaffordable action does not debit the wallet.

A hint receipt records a **complete replay witness**, not a random legal move. A repeated request for the same logical board in the same attempt is free, including equivalent within-tray slot arrangements, undo cycles and a cold resume. Every witness command is remapped to the actual slots and replayed to a win before its first step is shown. A solver timeout is reported as unknown and is free. Restarting creates a new attempt and new hint entitlements.

An extra tray is a session entitlement. It persists through Continue and undo. Undo restores the earlier food state, then adds the already-granted tray empty if the snapshot predates the purchase. It never copies foods from the current extra tray into an older snapshot. Restart and Next create a new attempt without the old extra tray. No second tray can be charged in that attempt.

Wallet, receipt, entitlement, profile and board effects are written in one checksummed save envelope. A failure before a durable write rolls back the in-memory debit and effect. Once a complete validated temporary envelope exists, the action is committed: if the final rename fails, startup recovers that same envelope rather than refunding an action that will reappear after restart. Tests inject both failure points.

Version 1 saves migrate to version 2 without changing earned coins, completed levels, settings or the saved campaign board. The welcome grant has its own idempotency key. If every save copy is damaged, each original is archived beside the save as `.corrupt.*` before fresh progress is written; an archive failure blocks replacement. Unknown future save schemas are preserved and blocked from writes. This is local corruption/recovery protection; it is not a trusted payment ledger or protection against device owners editing their files.

## Future payments and ads

The payment system is deliberately deferred. Before enabling real-money purchases, connect platform billing, obtain localized product prices, validate receipts through an authoritative service, use idempotent transaction IDs, support restore/refund/revocation, and decide account/cloud recovery policy. Never trust a client-supplied “success” callback or ship a method that directly turns arbitrary data into purchased coins.

An ad provider should later offer a clearly labeled optional reward, pause/save the stable board before leaving the app, and award it once only after verified completion. Unavailable, canceled, failed and duplicate callbacks must leave the wallet and puzzle coherent. None of those providers is claimed to exist in this build.

Change price constants and finish definitions in `services/economy_service.gd`. First-clear rewards remain in `SaveService.FIRST_CLEAR_COINS`. Completing the former final level 30 now unlocks level 31; campaign expansion itself does not grant another clear reward. Re-run economy, save and scene integration tests after changing any entitlement or transaction behavior.
