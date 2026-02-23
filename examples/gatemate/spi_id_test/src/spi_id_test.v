// -------------------------------------------------------
// MODULE: spi_id_test (SPI Flash Identification Test)
// @20260223 fm4dd
//
// Tested pmod-flash (https://github.com/fm4dd/pmod-flash)
// connected to PMODA on Gatemate E1 eval board v3.1B
// and Digilent pmodUSBUART connected to PMODB lower pinrow
// 
// FUNCTION: 
// This module performs a JEDEC "Read Identification" (RDID) test on an 
// external SPI Flash (specifically tested with Macronix MX25R series).
//
// OPERATION:
// 1. Waits for a Power-On Reset delay (~13ms) to ensure Flash IC is stable.
// 2. On trigger (RESET button), pulls CS_N low and sends command 0x9F.
// 3. Immediately reads 3 bytes (Manufacturer ID, Memory Type, Density).
// 4. Converts these binary bytes into Hexadecimal ASCII characters.
// 5. Sends the hex string (e.g., "C2 28 17") over UART at the defined Baud Rate.
// 6. Terminates the SPI session by pulling CS_N high and enters a DONE state.
// -------------------------------------------------------
`default_nettype none

module spi_id_test #(
    parameter TOTAL_BYTES   = 3,          // Standard JEDEC ID is 3 bytes
    parameter BAUD_RATE     = 1_000_000,  // Target Serial Speed
    parameter CLK_FREQ      = 10_000_000  // 10MHz System Clock
)(
    input  wire        CLK,           // 10MHz hardware clock
    input  wire        RESET,         // Button trigger (active high)
    output wire [7:0]  LEDS,          // Visual status
    output reg         SPIFLASH_CLK,  // SPI SCLK
    output reg         SPIFLASH_CS_N, // SPI Chip Select (Active Low)
    output reg         SPIFLASH_MOSI, // Master Out Slave In
    input  wire        SPIFLASH_MISO, // Master In Slave Out
    output wire        TXD            // UART Transmit
);

    // --- 1. Clock, Reset, and Power-Up Timing ---
    
    // Macronix MX25R chips require a delay (tVSL) after power reaches minimum VCC.
    // At 10MHz, 2^17 cycles is approx 13.1ms, well above the required 800us.
    reg [17:0] pwr_on_cnt = 0;
    wire pwr_ready = pwr_on_cnt[17];
    always @(posedge CLK) if (!pwr_ready) pwr_on_cnt <= pwr_on_cnt + 1;

    // Synchronous internal reset for the state machine
    reg [3:0] rst_cnt = 0;
    wire sys_rst = !rst_cnt[3];
    always @(posedge CLK) if (!rst_cnt[3]) rst_cnt <= rst_cnt + 1;

    // Button Edge Detection Logic
    // Detects the transition from 0 to 1 so the command runs only once per press
    reg [16:0] db_cnt = 0;   // ~6.5ms debounce at 10MHz
    reg        btn_state = 0;
    reg        reset_prev = 0;
    wire       reset_trigger;

    always @(posedge CLK) begin
        // If button matches current state, reset counter
        if (RESET == btn_state) begin
            db_cnt <= 0;
        end else begin
            // If button is different, count up until stable
            db_cnt <= db_cnt + 1;
            if (db_cnt[16]) begin
                btn_state <= RESET;
                db_cnt <= 0;
            end
        end
        // Standard edge detection on the debounced signal
        reset_prev <= btn_state;
    end
    assign reset_trigger = (btn_state == 1'b1 && reset_prev == 1'b0);

    // --- 2. State Machine & String ROM ---
    localparam IDLE       = 0, // Wait for button/power ready
               SEND_STR   = 1, // Sends the "Chip ID: " prefix
               CMD_SEND   = 2, // Shift out 8-bit command (0x9F)
               READ_BYTE  = 3, // Shift in 8-bit response from MISO
               HEX_CONV   = 4, // Convert byte to Hex ASCII characters
               UART_SEND  = 5, // Send ASCII characters over serial
               SEND_NL    = 6, // Sends \r\n at the end over serial
               DONE       = 7; // End SPI transaction (CS_N high)

    reg [2:0] state = IDLE;
    reg [3:0] str_ptr;         // Pointer for indexing the string/newline

    // Helper: String storage for "Chip ID: " (9 chars)
    // Using a function or case inside the state machine is cleaner for small strings
    reg [7:0] prefix_rom [0:8];
    initial begin
        prefix_rom[0]="C"; prefix_rom[1]="h"; prefix_rom[2]="i"; prefix_rom[3]="p"; 
        prefix_rom[4]=" "; prefix_rom[5]="I"; prefix_rom[6]="D"; prefix_rom[7]=":"; 
        prefix_rom[8]=" ";
    end

    // SPI/UART Registers
    reg [7:0] shift_reg, u_data;
    reg [3:0] bit_cnt;
    reg [1:0] byte_cnt, spi_divider, ascii_step;
    reg u_valid;
    wire u_ready;

    // Helper function: Converts 4-bit hex value to 8-bit ASCII character
    function [7:0] to_ascii;
        input [3:0] nibble;
        begin
            to_ascii = (nibble < 10) ? (8'h30 + nibble) : (8'h37 + nibble);
        end
    endfunction

    // --- 3. Main SPI Control Logic ---
    always @(posedge CLK) begin
        if (sys_rst) begin
            state <= IDLE; 
            SPIFLASH_CS_N <= 1; 
            SPIFLASH_CLK <= 0; 
            u_valid <= 0;
            SPIFLASH_MOSI <= 0;
        end else begin
            case (state)
                
                // [IDLE]: Wait for manual trigger and ensure Flash is powered up
                IDLE: begin
                    u_valid <= 0; 
                    SPIFLASH_CS_N <= 1;
                    SPIFLASH_CLK <= 0;
                    // Using reset_trigger (edge)
                    if (reset_trigger && pwr_ready) begin
                        state <= SEND_STR;
                        str_ptr <= 0; // Ensure prefix starts at index 0
                        state <= SEND_STR;
                        SPIFLASH_CS_N <= 0; // Assert Chip Select
                        shift_reg <= 8'h9F; // Load RDID Command
                        bit_cnt <= 0;
                        byte_cnt <= 0;
                        spi_divider <= 0;
                    end
                end

                // [SEND_STR]: Stream the prefix string to serial
                SEND_STR: begin
                    u_data <= prefix_rom[str_ptr];
                    u_valid <= 1;
                    if (u_ready && u_valid) begin
                        u_valid <= 0;
                        if (str_ptr == 8) state <= CMD_SEND;
                        else str_ptr <= str_ptr + 1;
                    end
                end

                // [CMD_SEND]: Transmit the 8-bit command (MSB first)
                CMD_SEND: begin
                    SPIFLASH_MOSI <= shift_reg[7]; 
                    spi_divider <= spi_divider + 1;
                    
                    // Clock Pattern: Low for 2 cycles, High for 2 cycles (2.5MHz)
                    if (spi_divider == 2'd0) SPIFLASH_CLK <= 0;
                    if (spi_divider == 2'd2) SPIFLASH_CLK <= 1; // Rising edge: Flash samples MOSI
                    
                    if (spi_divider == 2'd3) begin
                        spi_divider <= 0;
                        if (bit_cnt == 7) begin 
                            state <= READ_BYTE; // End of command, start reading reply
                            bit_cnt <= 0; 
                        end else begin 
                            bit_cnt <= bit_cnt + 1; 
                            shift_reg <= {shift_reg[6:0], 1'b0}; 
                        end
                    end
                end

                // [READ_BYTE]: Receive one byte of ID data from MISO pin
                READ_BYTE: begin
                    SPIFLASH_MOSI <= 0; // Drive 0 on MOSI while reading
                    spi_divider <= spi_divider + 1;
                    if (spi_divider == 2'd0) SPIFLASH_CLK <= 0;
                    if (spi_divider == 2'd2) SPIFLASH_CLK <= 1; // Rising edge: FPGA samples MISO
                    
                    if (spi_divider == 2'd3) begin
                        spi_divider <= 0;
                        shift_reg <= {shift_reg[6:0], SPIFLASH_MISO}; 
                        if (bit_cnt == 7) begin
                            state <= HEX_CONV; // Byte complete, go to display logic
                            bit_cnt <= 0;
                            ascii_step <= 0;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end
                
                // [HEX_CONV]: Prepare ASCII output for the serial monitor
                HEX_CONV: begin
                    case (ascii_step)
                        0: u_data <= to_ascii(shift_reg[7:4]); // Convert High 4 bits
                        1: u_data <= to_ascii(shift_reg[3:0]); // Convert Low 4 bits
                        2: u_data <= 8'h20;                    // Append ASCII Space (0x20)
                    endcase
                    u_valid <= 1; 
                    state <= UART_SEND;
                end

                // [UART_SEND]: Handshake with UART module to transmit character
                UART_SEND: begin
                    if (u_ready && u_valid) begin
                        u_valid <= 0;
                        if (ascii_step < 2) begin
                            ascii_step <= ascii_step + 1;
                            state <= HEX_CONV;
                        end else begin
                            // Check if we have retrieved all requested ID bytes
                            if (byte_cnt + 1 >= TOTAL_BYTES) begin
                               state <= SEND_NL; // Only go to newline after ALL bytes are done
                               str_ptr <= 0;     // IMPORTANT: Reset pointer to 0 for the \r\n sequence
                            end else begin 
                               byte_cnt <= byte_cnt + 1;
                               state <= READ_BYTE; // Go back to read the next SPI byte
                            end
                        end
                    end
                end

                // [SEND_NL]: Send Carriage Return and Line Feed to serial
                SEND_NL: begin
                    u_data <= (str_ptr == 0) ? 8'h0D : 8'h0A; // \r then \n
                    u_valid <= 1;
                    if (u_ready && u_valid) begin
                        u_valid <= 0;
                        if (str_ptr == 1) state <= DONE;
                        else str_ptr <= str_ptr + 1;
                    end
                end

                // [DONE]: Release Flash and wait for next trigger
                DONE: begin 
                    SPIFLASH_CS_N <= 1; // De-assert CS_N to finish SPI cycle
                    state <= IDLE;      
                end

                default: state <= IDLE;
            endcase
        end
    end

    // --- 4. UART Module Instance ---
    // Calculates bit timing based on 10MHz CLK_FREQ
    corescore_emitter_uart #(.clk_freq_hz(CLK_FREQ), .baud_rate(BAUD_RATE)) 
    uart_inst (.i_clk(CLK), .i_rst(sys_rst), .i_data(u_data), .i_valid(u_valid), .o_ready(u_ready), .o_uart_tx(TXD));

    // --- 5. Debug LEDs ---
    // LED logic is inverted for common-anode or active-low setups
    assign LEDS = ~{2'b0, pwr_ready, state, SPIFLASH_CS_N, SPIFLASH_MISO};

endmodule
