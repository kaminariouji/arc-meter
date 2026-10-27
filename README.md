# ArcMeter

Metered USDC payments between software. A consumer agent funds a channel, a provider agent withdraws what has accrued, the consumer takes back whatever was not spent. Built and tested in Arc Studio, deployed on Arc mainnet.

## Why

Agents that pay each other per call, per second or per token have two bad options today:

- **Push payments.** The consumer sends USDC to the provider after every unit of work. Every one of those transfers can fail, and a failed transfer leaves the work unpaid with no record of what was owed.
- **Prepaid credits.** The consumer hands over the whole amount up front and trusts the provider to keep a ledger. If the provider disappears, the money is gone.

A payment channel removes both. The consumer commits a deposit once, the provider takes what has actually accrued whenever it wants, and the consumer gets the remainder back with a single transaction. Neither side has to trust the other's bookkeeping, and no off-chain signature scheme is needed.

## How it works

```
open(id, provider, ratePerSecond, deposit)   consumer locks USDC, sets a rate
accrued(id)                                  view: what the provider can take right now
withdraw(id)                                 provider takes the accrued amount
topUp(id, amount)                            consumer extends the runway
close(id)                                    consumer settles the provider and refunds the rest
```

- Accrual is `elapsed * ratePerSecond`, **capped by the deposit**, so a channel can never overdraw.
- Withdrawing settles up to the current second; a second withdrawal in the same second reverts with `NothingToClaim` instead of paying twice.
- `close` pays the provider what has accrued and refunds `deposit - withdrawn - accrued` to the consumer. It can only be called by the consumer; `withdraw` can only be called by the provider.
- Channels are keyed by a caller-chosen `bytes32`, so a job id or a session id is the key. An id can never be reused, which means a stale id can never point at a new channel.
- `ratePerSecond` is capped at 1e15 base units per second, which keeps `elapsed * rate` far away from overflow.

## Deployed on Arc mainnet

| | |
|---|---|
| Chain | Arc mainnet, id **5042** |
| USDC | `0x3600000000000000000000000000000000000000` (6 decimals) |
| ArcMeter | `0x1076c9d746f27e5c2037006d8fc2f7fe6d2dd801` |
| Deploy tx | `0x3838c6563c9f9ed68caabdd8465d14f0f31c1cd487b8740209b030ecce870cf6` |

## Verify without a block explorer

`explorer.arc.io` sits behind a login, so every claim here is reproducible from the public RPC instead.

```bash
RPC=https://rpc.mainnet.arc.io

# bytecode is really there
curl -s -X POST $RPC -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_getCode","params":["0x1076c9d746f27e5c2037006d8fc2f7fe6d2dd801","latest"]}'

# the deployment receipt
curl -s -X POST $RPC -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_getTransactionReceipt","params":["0x3838c6563c9f9ed68caabdd8465d14f0f31c1cd487b8740209b030ecce870cf6"]}'
```

Raw receipts for every transaction in the demo are saved in `media/receipts.json`.

## Tests

12 Foundry tests, 12 passing: deposit pull, accrual over time, withdrawal, double withdrawal in the same second, provider-only withdraw, consumer-only close, close with refund, deposit exhaustion capping accrual, id reuse, top-up extending runway, withdrawal after close, and bad-parameter reverts.

The suite was written and run inside Arc Studio before deployment. The sandbox log is in `media/arc-studio-test-run.txt`; the project is at https://studio.arc.io/app/c49231bf-9c51-4b97-bd09-7ea77397de3c.

```bash
forge test
```

## The app

`index.html` is a single page: connect a wallet, load a channel by id, watch the accrued amount tick, withdraw as the provider, close and refund as the consumer. Reads go straight to `https://rpc.mainnet.arc.io`; writes go through the connected wallet.

## Layout

```
src/ArcMeter.sol            the contract
test/ArcMeter.t.sol         12 tests
test/mocks/MockUSDC.sol     6-decimal token for tests
index.html                  the app
media/arc-studio-test-run.txt   forge test output from the Arc Studio sandbox
media/receipts.json         raw receipts for the demo transactions
```
