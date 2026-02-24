## OnBoard Flash test program

### Description

This is a Verilog test program for the flash chip on PMOD Flash.
It only sends one command 9Fh (Read Identification - RDID), and returns the output to a serial console.

This code also works with the onboard Flash of the iCEBreaker board.

However by default, the onboard flash enters a Deep Power Down (DPD) mode after the bistream has been loaded.
When the Flash is in DPD, it ignores all standard commands—including RDID (0x9F).
Since it ignores the command, it never drives the MISO line, leaving it pulled high (reading as FF).

This means we either must wake the flash up from Deep Power Down (option A),
or (B) have the programming tell the board to disable Deep Power Down after loading the bitstream.

Option A is to add the DPD wake-up logic into the Verilog code before sending the RDID command.

For (B), we can tell bitstream generator program `icepack` to disable DPD mode.
This is done with the option `icepack -s`: disable final deep-sleep SPI flash command after bitstream is loaded

By adding `-s` into the Makefile, and we can query the onboard flash without additional coding.
In the Makefile, we can simply switch between onboard flash and pmod-flash by enabling the right constraints file.

iCEBreaker constraints for the onboard FLash:
```
## ##################################################
## iCEBreaker board constraints
## ##################################################
set_io -nowarn CLK        35 # 12 MHz clock
set_io -nowarn RXD         6
set_io -nowarn TXD         9
set_io -nowarn RESET      10

## ##################################################
## iCEbreaker onboard SPI Flash
## ##################################################
set_io -nowarn SPIFLASH_CLK  15
set_io -nowarn SPIFLASH_CS_N 16
set_io -nowarn SPIFLASH_MOSI 14
set_io -nowarn SPIFLASH_MISO 17

## ##################################################
## PMOD2 connector constraints for Digilent PMOD 8LD
## ##################################################
set_io -nowarn LEDS[7]     27
set_io -nowarn LEDS[6]     25
set_io -nowarn LEDS[5]     21
set_io -nowarn LEDS[4]     19
set_io -nowarn LEDS[3]     26
set_io -nowarn LEDS[2]     23
set_io -nowarn LEDS[1]     20
set_io -nowarn LEDS[0]     18
```

PMOD Flash module test on iCEBreaker FPGA:

<img src="images/pmod-flash-icebreaker.jpg" width="600px">

### Build FPGA Bitstream

```
$ make clean; make
rm -f spi_id_test.json spi_id_test.asc spi_id_test.rpt spi_id_test.bin spi_id_test.vcd spi_id_test.tb abc.history spi_id_test.tb
/home/fm/oss-cad-suite/bin/yosys -p 'synth_ice40 -top spi_id_test -json spi_id_test.json' src/spi_id_test.v src/emitter_uart.v

 /----------------------------------------------------------------------------\
 |  yosys -- Yosys Open SYnthesis Suite                                       |
 |  Copyright (C) 2012 - 2026  Claire Xenia Wolf <claire@yosyshq.com>         |
 |  Distributed under an ISC-like license, type "license" to see terms        |
 \----------------------------------------------------------------------------/
 Yosys 0.62+55 (git sha1 29a270c4b, clang++ 18.1.8 -fPIC -O3)
...
Info: Device utilisation:
Info: 	         ICESTORM_LC:     210/   5280     3%
Info: 	        ICESTORM_RAM:       0/     30     0%
Info: 	               SB_IO:      15/     96    15%
Info: 	               SB_GB:       3/      8    37%
Info: 	        ICESTORM_PLL:       0/      1     0%
Info: 	         SB_WARMBOOT:       0/      1     0%
Info: 	        ICESTORM_DSP:       0/      8     0%
Info: 	      ICESTORM_HFOSC:       0/      1     0%
Info: 	      ICESTORM_LFOSC:       0/      1     0%
Info: 	              SB_I2C:       0/      2     0%
Info: 	              SB_SPI:       0/      2     0%
Info: 	              IO_I3C:       0/      2     0%
Info: 	         SB_LEDDA_IP:       0/      1     0%
Info: 	         SB_RGBA_DRV:       0/      1     0%
Info: 	      ICESTORM_SPRAM:       0/      4     0%
...
Info: Program finished normally.
/home/fm/oss-cad-suite/bin/icetime -d up5k -mtr spi_id_test.rpt spi_id_test.asc
// Reading input .asc file..
// Reading 5k chipdb file..
// Creating timing netlist..
// Timing estimate: 20.52 ns (48.73 MHz)
/home/fm/oss-cad-suite/bin/icepack -s spi_id_test.asc spi_id_test.bin
```

### Board Programming
```
$ make prog
Programming to Flash:
/home/fm/oss-cad-suite/bin/iceprog spi_id_test.bin
init..
cdone: high
reset..
cdone: low
flash ID: 0xEF 0x40 0x18 0x00
file size: 104090
erase 64kB sector at 0x000000..
erase 64kB sector at 0x010000..
programming..
done.                 
reading..
VERIFY OK             
cdone: high
Bye.
```
### Output
On iCEBreaker we get to onboard UART typically as device /dev/ttyUSB1, we can display the serial data in a terminal window.

```
$ ./terminal.sh 
picocom v3.1

port is        : /dev/ttyUSB1
flowcontrol    : none
baudrate is    : 1000000
parity is      : none
databits are   : 8
stopbits are   : 1
escape is      : C-a
local echo is  : no
noinit is      : no
noreset is     : no
hangup is      : no
nolock is      : no
send_cmd is    : sz -vv
receive_cmd is : rz -vv -E
imap is        : 
omap is        : 
emap is        : crcrlf,delbs,
logfile is     : none
initstring     : none
exit_after is  : not set
exit is        : no

Type [C-a] [C-h] to see available commands
Terminal ready
Chip ID: EF 40 18 
Chip ID: EF 40 18 
Chip ID: EF 40 18 

Terminating...
Thanks for using picocom
```
Exit picocom with CTL-A followed by CTL-X.

Notice the device identification ID is "EF 40 18" = Winbond W25Q128.

* Manufacturer EF = Winbond
* memory type: 40 = W25Q series
* mem density: 18 = 128Mbit (16 Megabytes. Capacity 0x18 = 24 decimal, 2^24 bits = 16MB) 

If the module constraints are wrong and the SPI communication fails, the typical serial output becomes "FF FF FF".
