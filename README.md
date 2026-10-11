# I2C Master Controller (Verilog)

A single-master I2C controller that performs a START -> 7-bit address+W -> ACK ->
8-bit data -> ACK -> STOP write transaction, modeled on an open-drain SDA/SCL bus
with tri-state control, the way a real I2C peripheral driver works.

## Files
- `i2c_master.v` — synthesizable RTL: FSM-based I2C master (write transaction).
- `i2c_slave_model.v` — a minimal behavioral I2C slave used only to verify the
  master in simulation (not synthesizable; it's a test fixture, not a design).
- `tb_i2c.v` — self-checking testbench: runs 5 write transactions through the
  master into the slave model and checks the received address/data against
  what was sent.

## Design notes
- 4-phase SCL generation (low-low-high-high) per bit, parameterized by `CLK_DIV`.
- SDA is tri-stated (`sda_oe`) when the master must release the bus for the
  slave to drive the ACK bit — matching real open-drain I2C bus behavior.
- `ack_error` is asserted if a slave fails to pull SDA low during an ACK
  phase, modeling a NACK / no-response condition.

## Bug found and fixed during verification
The first version of the behavioral slave model shifted in a bit on every
SCL rising edge without excluding the ACK bit's own clock pulse, which
corrupted every byte after the first (confirmed by the self-checking
testbench — 4 of 5 writes failed with misaligned data). Fixed by making the
slave an explicit state machine (`S_ADDR -> S_ADDR_ACK -> S_DATA -> S_DATA_ACK`)
that only shifts in bits during the `S_ADDR`/`S_DATA` states, so the ACK bit
is driven, not sampled. All 5 tests pass after the fix.

## Running the simulation
Requires Icarus Verilog (`iverilog`/`vvp`), which this project was built and
tested with.

```bash
iverilog -g2012 -o sim i2c_master.v i2c_slave_model.v tb_i2c.v
vvp sim
```

### Example output
```
[PASS] test 0: addr 0x50 data 0x00 received correctly
[PASS] test 1: addr 0x50 data 0xff received correctly
[PASS] test 2: addr 0x50 data 0xa5 received correctly
[PASS] test 3: addr 0x50 data 0x3c received correctly
[PASS] test 4: addr 0x50 data 0x99 received correctly
--------------------------------------------------
I2C master write test summary: 5 passed, 0 failed (of 5)
--------------------------------------------------
RESULT: ALL TESTS PASSED
```

A separate NACK-path test (no slave present on the bus) was also run and
confirmed `ack_error` asserts correctly when nothing ACKs the address.
