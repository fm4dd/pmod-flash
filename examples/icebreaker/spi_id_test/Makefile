### ------------------------------------------------------------ ###
### Gatemate Makefile for oss-cad-suite toolchain (2026-02-11)   ###
###                                                              ###
### Central Makefile                                             ###
### ------------------------------------------------------------ ###
### toolchain location
TOOLPATH = /home/fm/oss-cad-suite/bin
PIN_DEF  = src/icebreaker.pcf
DEVICE   = up5k
PACKAGE  = sg48

PROJ     = spi_id_test
ADD_SRC  = src/emitter_uart.v

all: $(PROJ).rpt $(PROJ).bin

%.json: src/%.v
	$(TOOLPATH)/yosys -p 'synth_ice40 -top $(PROJ) -json $@' $< $(ADD_SRC)

%.asc: %.json
	$(TOOLPATH)/nextpnr-ice40 --package $(PACKAGE) --$(DEVICE) --asc $@ --pcf $(PIN_DEF) --json $^

%.bin: %.asc
	$(TOOLPATH)/icepack $< $@

%.rpt: %.asc
	$(TOOLPATH)/icetime -d $(DEVICE) -mtr $@ $<

test:
	@echo 'Running testbench simulation'
	test ! -e $(PROJ).tb || rm $(PROJ).tb
	test ! -e $(PROJ).vcd || rm $(PROJ).vcd
	$(TOOLPATH)/iverilog -DBENCH -o $(PROJ).tb -s $(PROJ)_tb ./*.v
	$(TOOLPATH)/vvp $(PROJ).tb

prog: $(PROJ).bin
	@echo 'Programming to Flash:'
	$(TOOLPATH)/iceprog $<

clean:
	rm -f $(PROJ).json $(PROJ).asc $(PROJ).rpt $(PROJ).bin $(PROJ).vcd $(PROJ).tb abc.history $(PROJ).tb

.SECONDARY:
.PHONY: all prog test clean
