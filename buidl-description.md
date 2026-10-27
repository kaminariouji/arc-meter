# ArcMeter

Software that bills per second has no good way to pay. A push transfer after every unit of work can fail and leaves the work unpaid; prepaying the whole amount asks the buyer to trust the seller's ledger. ArcMeter is a metered payment channel: the buyer funds a deposit once, the seller takes what has actually accrued whenever it wants, and the buyer gets the remainder back in one transaction.

## How it works

1. `open(id, provider, ratePerSecond, deposit)` pulls USDC from the consumer and records a rate.
2. `accrued(id)` is `elapsed * ratePerSecond`, capped by the deposit, so a channel can never overdraw.
3. `withdraw(id)` pays the provider everything accrued since the last settlement. A second call in the same second reverts with `NothingToClaim` instead of paying twice.
4. `close(id)` pays the provider what has accrued and refunds `deposit - withdrawn - accrued` to the consumer. Only the consumer can close; only the provider can withdraw.
5. `topUp(id, amount)` extends the runway without reopening.

Channels are keyed by a caller-chosen `bytes32`, so a job id or a session id is the key, and an id can never be reused.

## Live on Arc mainnet (chain id 5042)

Contract: 0x1076c9d746f27e5c2037006d8fc2f7fe6d2dd801
Deploy tx: 0x3838c6563c9f9ed68caabdd8465d14f0f31c1cd487b8740209b030ecce870cf6

One real channel, 0.05 USDC at 0.0001 USDC per second, opened and closed after 286 seconds:
open 0x2c9131085eb2af73534c954fcf7161188cb7a9a4da9ec3795947f2f260df7f21
close 0xc1d01b9e8c336ef7055e736895d624ce26051ba5a1bb7553e3fb359ba5232a17

The close transaction pays the provider 0.0286 USDC and refunds 0.0214 USDC to the consumer in the same call. Arc's explorer sits behind a login, so media/receipts.json holds the raw receipts read from https://rpc.mainnet.arc.io and the README has the one-line curl to re-run each check.

## Built in Arc Studio

The contract and its 12 tests were placed, compiled and run inside the Arc Studio workspace for this project: https://studio.arc.io/app/c49231bf-9c51-4b97-bd09-7ea77397de3c. The sandbox log of that run is saved at media/arc-studio-test-run.txt. Studio does not deploy to mainnet on your behalf, so the mainnet contract above was deployed from the builder's own wallet, signed in the wallet itself.

## Tests

12 Foundry tests, 12 passing: deposit pull, accrual over time, withdrawal, double withdrawal in the same second, provider-only withdraw, consumer-only close, close with refund, deposit exhaustion capping accrual, id reuse, top-up extending runway, withdrawal after close, and bad-parameter reverts.

## Why it fits this round

Software-to-software payments is one of the directions the round names. The app at https://arc-meter.pages.dev reads the channel straight from the Arc RPC and shows the accrued amount, the deposit and the closed state without any backend.