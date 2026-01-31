# vesc-daly-bms
Daly Smart BMS (BLE UART) integration with VESC (using VESC Express)

\* To run more than 1 Lisp script on VESC / VESC Express the scripts can be merged together. Tested by running this nice [LED Control for VESC Express](https://gist.github.com/Relys/8268e53af4d9e995f1b4672893aac4a0) LCM script by Relys with my DALY BMS script merged together.

## Things needed
- **VESC Express.** *It might be fully possible to do this on **VESC**, but some small changes are required. Mainly with uart-start and PC817 pin to wake BMS up (PPM/Servo pin?)*
- **PC817 opto-isolator.** It is **optional**, it is used to wake DALY BMS automatically on script start by emulating wake button press (that same button that is on Daly BLE module). If not used then BMS can be waked up by charger plugged in or discharge current >2A (as per Daly's website). When BMS is in charge-only configuration, the opto-isolator to emulate the button press is a nice-to-have option, making automatic BMS wake-up on script start more convenient.
**⚠️ DO NOT CONNECT S1 (WAKE PIN) DIRECTLY TO VESC/VESC EXPRESS ⚠️ 36V is present on that pin for 12S BMS ⚠️**
- **330 Ohm - 1 kOhm resistor**, to limit opto-isolator's LED current. *Optional if PC817 is not used.*
- **MicroUSB breakout board**, for convenience of using provided UART cable and/or connecting Daly BLE module back to use it for BMS configuration.


## TODO
- [x] Number of cells
- [x] Individual cell voltages
- [x] Current
- [x] Cells temperature
- [x] SOC
- [ ] Reimplement UART buffer clearing, uart-stop + uart-start is very crude
- [ ] Errors: ERRORS -> 'bms-status
- [ ] Charge Enable / Charge Disable
- [ ] Balance state: CELL_BALANCE_STATE cmd_id -> 'bms-bal-state
- [ ] Min and max temps: MIN_MAX_TEMPERATURE cmd_id-> 'bms-temp-cell-max

## Connections
![Connection schematics](connection_sketchmatic.png?raw=true "Connections")

## VESC Tool
![VESC Tool BMS section](vesc_tool_screenshot.png?raw=true "VESC Tool BMS section")