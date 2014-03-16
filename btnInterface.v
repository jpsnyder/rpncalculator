`timescale 1ns / 1ps
module btnInterface(
   input wire push,  // ENTER button  (BTN1)
	input wire plusTimes,  // BTN2
	input wire minusDivide,  // BTN3
	input wire debEN,   // debounce enable (BTN4)
   input wire [7:0] sw,
	input wire clk,
   output wire [6:0] seg,
   output wire [3:0] an
	);
	
	// BRAM variables
	reg [31:0] answer;
	reg [7:0] addra, addrb;
	reg [0:0] wea, web;
	//reg [15:0] dina;
	reg [15:0] dinb;
	wire [15:0] douta;
	wire [15:0] doutb;
	
   reg [25:0] count; // for DELAY state
	reg [3:0] writeCount; // for writing
	
	// DIVIDER variables	
	reg divide_start, divide_rst;
	wire [15:0] divide_quotient;
	wire divide_done;
	
	// DISP variables
	reg [15:0] display;  // Value currently displaying
	reg [3:0] extraChar; // extra character enable

	// State machine variabeles
	reg [3:0] state, prevState;
	localparam IDLE = 0;
	localparam PUSH = 1;
	localparam ADD = 2;
	localparam MULTI = 3;
	localparam SUB = 4;
	localparam DIVIDE = 5;
	localparam DELAY = 6;			// delay for a second to display value on 7seg
	localparam ERROR = 7;			// not enough operands
	localparam WRITE = 8;
	localparam ERRCheck = 9;
	localparam CALCULATE = 10;
	localparam CLEAR = 11;

	
	// Extra characters for statements like "Err", "Add ", "MNU5", "d1dE", "5Ub", "-"
	localparam r = 4'b0000;  // lower case r
	localparam NEG = 4'b0001;  // negative sign
	localparam P = 4'b0010;
	localparam L = 4'b0011;
	localparam U = 4'b0100;
	localparam M = 4'b0101;  // a,c,e are lit up
	localparam N = 4'b0110;
	localparam BLANK = 4'b0111;

	initial begin
		state <= IDLE;
		display <= 0;
		extraChar <= 0;
		count <= 0;
		addra <= 0;
		addrb <= -1;
		divide_start <= 0;
		divide_rst <= 0;
	end

	debouncer D1 (.btn_in(push), .enable(~debEN), .btn_out(push_out), .clk(clk));
	debouncer D2 (.btn_in(plusTimes), .enable(~debEN), .btn_out(plus_out), .clk(clk));
	debouncer D3 (.btn_in(plusTimes), .enable(debEN), .btn_out(times_out), .clk(clk));
	debouncer D4 (.btn_in(minusDivide), .enable(~debEN), .btn_out(minus_out), .clk(clk));
	debouncer D5 (.btn_in(minusDivide), .enable(debEN), .btn_out(divide_out), .clk(clk));
	debouncer D6 (.btn_in(push), .enable(debEN), .btn_out(clear_out), .clk(clk));

	simpleDivider DIVIDER(
		.dividend(doutb),
		.divisor(douta),
		.clk(clk),
		.start(divide_start),
		.reset(divide_rst),
		.done(divide_done),
		.Q(divide_quotient)
	);

	BRAM Ram (
		.clka(clk), // input clka
		.wea(wea), // input [0 : 0] wea
		.addra(addra), // input [7 : 0] addra
		//.dina(dina), // input [15 : 0] dina
		.douta(douta), // output [15 : 0] douta
		.clkb(clk), // input clkb
		.web(web), // input [0 : 0] web
		.addrb(addrb), // input [7 : 0] addrb
		.dinb(dinb), // input [15 : 0] dinb
		.doutb(doutb) // output [15 : 0] doutb
	);

	// Convert display to proper an and seg
	sevenSeg DISP (.digits(display), .extraChar(extraChar), .clk(clk), .an(an), .seg(seg));

	always @ (posedge clk) begin
		case (state)
		IDLE: begin
			if (addra == 0) begin
				extraChar <= 4'b1111;
				display <= {BLANK, BLANK, BLANK, BLANK}; // display nothing when nothing in stack
			end else begin
				extraChar <= 0;
				display <= doutb;  // display top of stack
			end
			state <= push_out ? PUSH : plus_out ? ADD : times_out ? MULTI
					: minus_out ? SUB : divide_out ? DIVIDE : clear_out ? CLEAR : IDLE;
		end
		CLEAR: begin
			addra <= 0;  // reset pointers
			addrb <= -1;
			state <= IDLE;
		end
		PUSH: begin
			addra <= addra + 1;
			addrb <= addrb + 1;
			web <= 1;
			dinb <= sw;
			extraChar <= 4'b0101;
			display <= { 4'hE, N, 4'h7, r };   // display "EN7r"
			state <= DELAY;
		end
		ADD: begin
			if (addra < 2) begin  // need at least 2 operands on stack to run
				state <= ERROR;
			end else begin
				addra <= addra - 1;
				addrb <= addrb - 1;
				extraChar <= 4'b0001;
				display <= { 4'hA, 4'hD, 4'hD, BLANK };   // display "Add "
				prevState <= state;
				state <= CALCULATE;
			end
		end
		MULTI: begin
			if (addra < 2) begin
				state <= ERROR;
			end else begin
				addra <= addra - 1;
				addrb <= addrb - 1;
				extraChar <= 4'b1110;
				display <= { M, U, L, 4'h7 };  // display "MUL7"
				prevState <= state;
				state <= CALCULATE;
			end
		end
		SUB: begin
			if (addra < 2) begin
				state <= ERROR;
			end else begin
				addra <= addra - 1;  // decrement pointers
				addrb <= addrb - 1;
				extraChar <= 4'b0101;
				display <= { 4'h5, U, 4'hB, BLANK };  // display "5Ub "
				prevState <= state;
				state <= CALCULATE;
			end
		end
		DIVIDE: begin
			if (addra < 2) begin
				state <= ERROR;
			end else begin
				addra <= addra - 1;  // decrement pointers
				addrb <= addrb - 1;
				divide_rst <= 1;
				extraChar <= 0;
				display <= { 4'hD, 4'h1, 4'hD, 4'hE };    // display "d1dE"
				prevState <= state;
				state <= CALCULATE;
			end
		end
		CALCULATE: begin
			if (count == 1) begin		// wait for a clock tick to pass before grabing operands
				case (prevState)  // which operator we came from
					ADD: begin
						answer <= douta + doutb;
						state <= ERRCheck;  // after calculation check for overflow
					end
					SUB: begin
						answer <= doutb + ~douta + 1;			
						state <= ERRCheck;  // after calculation check for overflow
					end
					DIVIDE: begin
						if (douta == 0) begin   // error if dividing by 0
							state <= ERROR;
						end else begin
							divide_rst <= 0;
							divide_start <= 1;
							if (divide_done) begin
								answer <= divide_quotient;
								divide_start <= 0;
								state <= WRITE;  // there will be no overflow, we can go right to write
							end else begin
								state <= CALCULATE;  // spin till division is done
							end
						end
					end
					MULTI: begin
						answer <= douta * doutb;	
						state <= ERRCheck;  // after calculation check for overflow
					end
				endcase
				count <= 0;   // before we leave, reset counter
			end else begin
				count <= count + 1;
				state <= CALCULATE; // cycle again to give time to BRAM to read
			end
		end
		ERRCheck: begin
			if (answer[31:16] == 0 || answer[31:16] == 16'hFFFF) begin  // check overflow
				state <= WRITE;
			end else begin
				addra <= addra + 1;  // increment pointers (we don't want to write anything)
				addrb <= addrb + 1;
				state <= ERROR;
			end
		end
		WRITE: begin
			dinb <= answer[15:0]; 
			web <= 1;
			state <= DELAY;
		end
		DELAY: begin
			if (count == 30000000) begin		// 30000000 display for less than a second
				count <= 0;   // before we leave, reset counter
				state <= IDLE;
			end else begin
				wea <= 0;
				web <= 0;
				count <= count + 1;
				state <= DELAY;
			end
		end
		ERROR: begin
			extraChar <= 4'b0111;
			display <= { 4'hE, r, r, BLANK };    // display "Err "
			state <= DELAY;
		end
		endcase
	end

endmodule

module debouncer (
   input btn_in,
   input clk,
	input enable,
   output reg btn_out
   );

   reg [17:0] count;

   reg [1:0] state;

   localparam READ = 0;    // read btn_in
   localparam IGNORE = 1;  // ignore btn_in
   localparam PULSE = 2;
   localparam DELAY = 3;   // delay while btn_in stablizes to low

   initial begin
      state <= READ;
   end

   always @ (posedge clk) begin
      count <= count + 1;
      if (btn_out) begin
         btn_out <= 0;
      end
      case (state)
         READ: begin
            state <= (btn_in && enable) ? PULSE : READ;
         end
         PULSE: begin
            count <= 0;
            btn_out <= 1;   // start pulse
            state <= IGNORE;
         end
         IGNORE: begin
            btn_out <= 0;   // end pulse
            if (count == 150000) begin	// 150000
               count <= 0;
               state <= ~btn_in ? DELAY : IGNORE;
            end else begin
               count <= count + 1;
            end
         end
         DELAY: begin
            if (count == 150000) begin		// 150000
               state <= READ;
            end else begin
               count <= count + 1;
            end
         end
      endcase
   end

endmodule


module sevenSeg (
   input [15:0] digits,
   input clk,
   input [3:0] extraChar,   // Enable extraChar for particular digit 
   output reg [3:0] an,
   output reg [6:0] seg // seg 0-6 <-> a-g
   );

   reg [16:0] count;   // count to downclock to 1kHz
   reg [3:0] Q;  // current digit
	

   initial begin
      Q[3:0] = 4'b0000;
	   an[3:0] = 4'b1110;
	   count = 1;
   end

   // Anode Driver
   always @ (posedge clk) begin
      if(count == 50000) begin // 50000 for 1kHz
         count = 1;
         if (~an[0]) begin
            an[0] = 1;
            Q[3:0] = digits[7:4];  // display till next clock cycle
            an[1] = 0;
         end else if (~an[1]) begin
            an[1] = 1;
            Q[3:0] = digits[11:8];
            an[2] = 0;
         end else if (~an[2]) begin
            an[2] = 1;
            Q[3:0] = digits[15:12];
            an[3] = 0;
         end else begin
            an[3] = 1;
            Q[3:0] = digits[3:0];
            an[0] = 0;
         end
      end else begin
         count = count + 1;
      end
   end

   // Segment  #          abc_defg  
   localparam ZERO = 7'b000_0001; 
   localparam ONE  = 7'b100_1111; 
   localparam TWO = 7'b001_0010; 
   localparam THREE = 7'b000_0110; 
   localparam FOUR = 7'b100_1100; 
   localparam FIVE = 7'b010_0100; 
   localparam SIX = 7'b010_0000;
   localparam SEVEN = 7'b000_1111;
   localparam EIGHT = 7'b000_0000; 
   localparam NINE = 7'b000_0100; 
   localparam A = 7'b000_1000;
   localparam B = 7'b110_0000;
   localparam C = 7'b011_0001;
   localparam D = 7'b100_0010;
   localparam E = 7'b011_0000;
   localparam F = 7'b011_1000;

   localparam r = 7'b111_1010;
   localparam NEG = 7'b111_1110;
   localparam P = 7'b001_1000;
   localparam L = 7'b111_0001;
   localparam U = 7'b100_0001;
   localparam M = 7'b010_1011;
   localparam N = 7'b000_1001;


	always @(an) begin
		if ((extraChar & ~an) == ~an) begin
			case (Q)
				0: seg <= r;
				1: seg <= NEG;
				2: seg <= P;
				3: seg <= L;
				4: seg <= U;
				5: seg <= M;
				6: seg <= N;
				default: seg <= 7'b111_1111;
			endcase
		end else begin
			case (Q)
				0: seg <= ZERO;
				1: seg <= ONE;
				2: seg <= TWO;
				3: seg <= THREE;
				4: seg <= FOUR;
				5: seg <= FIVE;
				6: seg <= SIX;
				7: seg <= SEVEN;
				8: seg <= EIGHT;
				9: seg <= NINE;
				10: seg <= A;
				11: seg <= B;
				12: seg <= C;
				13: seg <= D;
				14: seg <= E;
				15: seg <= F;
				default: seg <= 7'b111_1111;
			endcase
		end
	end

endmodule


module simpleDivider (
   input [15:0] dividend,
	input [15:0] divisor,
   input clk,
	input start,
	input reset,
	output reg done,
	output reg [15:0] Q
   );

	reg [15:0] R;
	
	always @ (posedge clk) begin
		if (reset) begin
			done = 0;
			Q = 0;
			R = dividend;
		end else if (start) begin
			if ( R >= divisor) begin
				Q = Q + 1;
				R = R - divisor;
			end else begin
				done = 1;
			end
		end
	end
	
endmodule
