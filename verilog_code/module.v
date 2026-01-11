`timescale 1ns/1ps
module TOP(
    Clk,
    Rst_n,
    Rx,
    Tx,
    RxData,
    TxData,
    TxEn
);

input           Clk;
input           Rst_n;
input           Rx;
input  [7:0]    TxData;    // new input
input           TxEn;      // new input
output          Tx;
output [7:0]    RxData;

wire [7:0]     TxData_internal; // for clarity
wire           TxDone;
wire           RxDone;
wire           tick;
wire [3:0]     NBits;
wire [15:0]    BaudRate;

assign NBits = 4'b1000;
assign BaudRate = 16'd325;

// Instantiate RX
UART_rs232_rx I_RS232RX(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .RxEn(1'b1),
    .RxData(RxData),
    .RxDone(RxDone),
    .Rx(Rx),
    .Tick(tick),
    .NBits(NBits)
);

// Instantiate TX
UART_rs232_tx I_RS232TX(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .TxEn(TxEn),
    .TxData(TxData),
    .TxDone(TxDone),
    .Tx(Tx),
    .Tick(tick),
    .NBits(NBits)
);

// Baud rate generator
UART_BaudRate_generator I_BAUDGEN(
    .Clk(Clk),
    .Rst_n(Rst_n),
    .Tick(tick),
    .BaudRate(BaudRate)
);

endmodule



/*Imagine that the baud rate you want to work with is 9600. The clock of my
FPGA is 50MHz. If we want the "TICKS" to ahev 16 times the frequency of the UART signal
we need a frequency 16 times the 9600Hz. 
The width of the UART signal is 1/9600 equal to 104us. The width of the main clock is 1/50Mhz equal to 20ns
How many 20ns pulses we need to cont to get to 104us/16??? Well (104000ns/16)/ 20ns = 325 pulses (
That's why in the top we set baud rate to 325)
*/
module UART_BaudRate_generator(
    Clk                   ,
    Rst_n                 ,
    Tick                  ,
    BaudRate
    );

input           Clk                 ; // Clock input
input           Rst_n               ; // Reset input
input [15:0]    BaudRate            ; // Value to divide the generator by
output          Tick                ; // Each "BaudRate" pulses we create a tick pulse
reg [15:0]      baudRateReg         ; // Register used to count


always @(posedge Clk or negedge Rst_n)
    if (!Rst_n) baudRateReg <= 16'b1;
    else if (Tick) baudRateReg <= 16'b1;
         else baudRateReg <= baudRateReg + 1'b1;
assign Tick = (baudRateReg == BaudRate);
endmodule

module UART_rs232_tx (Clk,Rst_n,TxEn,TxData,TxDone,Tx,Tick,NBits);	//Define my module as UART_rs232_tx

input Clk, Rst_n, TxEn,Tick;	//Define 1 bit inputs
input [3:0]NBits;		//Define 4 bits inputs
input [7:0]TxData;		//Define 8 bit inputs

output Tx;
output TxDone;




//Variabels used for state machine...
parameter  IDLE = 1'b0, WRITE = 1'b1;	//We have 2 states for the State Machine state 0 and 1 (WRITE adn IDLE)
reg  State, Next;			//Create some registers for the states
reg  TxDone = 1'b0;			//Variable used to notify when the transmission process is done
reg  Tx;				//We register the input value
reg write_enable = 1'b0;		//Variable used to activate or deactivate the transmission process			
reg start_bit = 1'b1;			//Variable used to notify if the START bit was made or not yet
reg stop_bit = 1'b0;			//Variable used to notify if the STOP bit was made or not yet
reg [4:0] Bit = 5'b00000;		//Variable used for the bit by bit write loop (in this case 8 bits so 8 loops)
reg [3:0] counter = 4'b0000;		//Counter variable used to count the tick pulses up to 16
reg [7:0] in_data=8'b00000000;		//Register where we store tha data that arrived with the TxData input and has to be sent
reg [1:0] R_edge;			//Variable used to avoid debounce of the write enable pin
wire D_edge;				//Wire used to connect the D_edge



///////////////////////////////STATE MACHINE////////////////////////////////
////////////////////////////////////////////////////////////////////////////
///////////////////////////////////Reset////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
always @ (posedge Clk or negedge Rst_n)			//It is good to always have a reset always
begin
if (!Rst_n)	State <= IDLE;				//If reset pin is low, we get to the initial state which is IDLE
else 		State <= Next;				//If not we go to the next state
end




////////////////////////////////////////////////////////////////////////////
////////////////////////////Next step decision//////////////////////////////
////////////////////////////////////////////////////////////////////////////
/* This is easy as well.  Each time "State or D_edge or TxData or TxDone" will 
change their value we decide which is the next step. 
 - If D_edge was detected, so the TxEn was enabeled, we start the write process
 - Obviously, if the TxDone is high, then we get back to IDLE and wait for next TxEn to be activated */
always @ (State or D_edge or TxData or TxDone) 
begin
    case(State)	
	IDLE:	if(D_edge)		Next = WRITE;		//If we are into IDLE and D_edge gets activated, we start the WRITE process
		else			Next = IDLE;
	WRITE:	if(TxDone)		Next = IDLE;  		//If we are into WRITE and TxDone gets high, we get back to IDLE and wait
		else			Next = WRITE;
	default 			Next = IDLE;
    endcase
end



////////////////////////////////////////////////////////////////////////////
///////////////////////////ENABLE WRITE OR NOT//////////////////////////////
////////////////////////////////////////////////////////////////////////////
always @ (State)
begin
    case (State)
	WRITE: begin
		write_enable <= 1'b1;	//If we are in the WRITE state, we enable the write process
	end
	
	IDLE: begin
		write_enable <= 1'b0;	//If we are in the IDLE state, we disable the write process
	end
    endcase
end





////////////////////////////////////////////////////////////////////////////
///////////////////////Write the data out on Tx pin/////////////////////////
////////////////////////////////////////////////////////////////////////////
/*Finally, each time we detect a Tick pulse, if the write_enable is enabeled,
we start counting ticks. First we set the Tx pin to LOW and that indicates a start bit.
Then each 16 ticks, we set the Tx output to a value acording to the "in_data" value which
is the data to eb sent. We do that by shifting the "in_data" using this lines: 
	in_data <= {1'b0,in_data[7:1]};
	Tx <= in_data[0]; */

always @ (posedge Tick)
begin

	if (!write_enable)				//if write_enable is not activated, then we reset all varaibles for enxt loop
	begin
	TxDone = 1'b0;
	start_bit <=1'b1;
	stop_bit <= 1'b0;
	end

	if (write_enable)				//if write_enable is activated, then we start counting and changing the Tx output
	begin
	counter <= counter+1;				//Increase the counter by one each positive edge of the Tick input
	
	
	if(start_bit & !stop_bit)			//We set the Tx to LOW (start bit) and pass the TxData input to the in:data register
	begin
	Tx <=1'b0;					//Create start bit  (low pulse)
	in_data <= TxData;				//Pass the data to eb sent to the in_data register so we could use it
	end		

	if ((counter == 4'b1111) & (start_bit) )	//If counter reaches 16 (4'b1111), then we create the first bit and set "start_bit" to low
	begin		
	start_bit <= 1'b0;
	in_data <= {1'b0,in_data[7:1]};
	Tx <= in_data[0];
	end


	if ((counter == 4'b1111) & (!start_bit) &  (Bit < NBits-1))	//If we reach 16 once again, we make a loop for the next 7 bits (NBits-1)
	begin		
	in_data <= {1'b0,in_data[7:1]};
	Bit<=Bit+1;
	Tx <= in_data[0];
	start_bit <= 1'b0;
	counter <= 4'b0000;
	end	



	
	if ((counter == 4'b1111) & (Bit == NBits-1) & (!stop_bit))	//We finish, so we set Tx to HIGH (Stop bit)
	begin
	Tx <= 1'b1;	
	counter <= 4'b0000;	
	stop_bit<=1'b1;
	end

	if ((counter == 4'b1111) & (Bit == NBits-1) & (stop_bit) )	//If stop bit was enabeled, than we reset the values and wait for enxt write process
	begin
	Bit <= 4'b0000;
	TxDone <= 1'b1;
	counter <= 4'b0000;
	//start_bit <=1'b1;
	end
	
	end
		

end



////////////////////////////////////////////////////////////////////////////
////////////////////////////Input enable detect/////////////////////////////
////////////////////////////////////////////////////////////////////////////
/*Here we detect if there was a reset or if the TxEn was activated.
If "TxEn" was actiavted than we start the write process and we will send
the data that is on the "TxData" input so amke sure that in the 
moment you activate "TxEn" the TxData" has the values you want to send . */
always @ (posedge Clk or negedge Rst_n)
begin

	if(!Rst_n)
	begin
	R_edge <= 2'b00;
	end
	
	else
	begin
	R_edge <={R_edge[0], TxEn};
	end
end
assign D_edge = !R_edge[1] & R_edge[0];





endmodule

module UART_rs232_rx (Clk,Rst_n,RxEn,RxData,RxDone,Rx,Tick,NBits);		//Define my module as UART_rs232_rx

input Clk, Rst_n, RxEn,Rx,Tick;		//Define 1 bit inputs
input [3:0]NBits;			//Define 4 bits inputs


output RxDone;				//Define 1 bit output
output [7:0]RxData;			//Define 8 bits output (this will eb the 1byte received data)


//Variabels used for state machine...
parameter  IDLE = 1'b0, READ = 1'b1; 	//We haev 2 states for the State Machine state 0 and 1 (READ adn IDLE)
reg [1:0] State, Next;			//Create some registers for the states
reg  read_enable = 1'b0;		//Variable that will enable or NOT the data in read
reg  start_bit = 1'b1;			//Variable used to notify when the start bit was detected (first falling edge of RX)
reg  RxDone = 1'b0;			//Variable used to notify when the data read process is done
reg [4:0]Bit = 5'b00000;		//Variable used for the bit by bit read loop (in this case 8 bits so 8 loops)
reg [3:0] counter = 4'b0000;		//Counter variable used to count the tick pulses up to 16
reg [7:0] Read_data= 8'b00000000;	//Register where we store the Rx input bits before assigning it to the RxData output
reg [7:0] RxData;			//We register the output as well so we store the value





///////////////////////////////STATE MACHINE////////////////////////////////
////////////////////////////////////////////////////////////////////////////
///////////////////////////////////Reset////////////////////////////////////
////////////////////////////////////////////////////////////////////////////
always @ (posedge Clk or negedge Rst_n)			//It is good to always have a reset always
begin
if (!Rst_n)	State <= IDLE;				//If reset pin is low, we get to the initial state which is IDLE
else 		State <= Next;				//If not we go to the next state
end




////////////////////////////////////////////////////////////////////////////
////////////////////////////Next step decision//////////////////////////////
////////////////////////////////////////////////////////////////////////////
/*This is easy. Each time "State or Rx or RxEn or RxDone" will change their value
we decide which is the next step. 
	- Obviously we get to IDLE only when RxDone is high
meaning that the read process is done.
	- Also, while we are into IDEL, we get to READ state only if Rx input gets low meaning
we've detected a start bit*/
always @ (State or Rx or RxEn or RxDone)
begin
    case(State)	
	IDLE:	if(!Rx & RxEn)		Next = READ;	 //If Rx is low (Start bit detected) we start the read process
		else			Next = IDLE;
	READ:	if(RxDone)		Next = IDLE; 	 //If RxDone is high, than we get back to IDLE and wait for Rx input to go low (start bit detect)
		else			Next = READ;
	default 			Next = IDLE;
    endcase
end






////////////////////////////////////////////////////////////////////////////
///////////////////////////ENABLE READ OR NOT///////////////////////////////
////////////////////////////////////////////////////////////////////////////
always @ (State or RxDone)
begin
    case (State)
	READ: begin
		read_enable <= 1'b1;			//If we are in the Read state, we enable the read process so in the "Tick always" we start getting the bits
	      end
	
	IDLE: begin
		read_enable <= 1'b0;			//If we get back to IDLE, we desable the read process so the "Tick always" could continue without geting Rx bits
	      end
    endcase
end





////////////////////////////////////////////////////////////////////////////
///////////////////////////Read the input data//////////////////////////////
////////////////////////////////////////////////////////////////////////////
/*Finally, each time we detect a Tick pulse,we increase a couter.
- When the counter is 8 (4'b1000) we are in the middle of the start bit
- When the counter is 16 (4'b1111) we are in the middle of one of the bits
- We store the data by shifting the Rx input bit into the Read_data register 
using this line of code: Read_data <= {Rx,Read_data[7:1]};
*/
always @ (posedge Tick)

	begin
	if (read_enable)
	begin
	RxDone <= 1'b0;							//Set the RxDone register to low since the process is still going
	counter <= counter+1;						//Increase the counter by 1 with each Tick detected
	

	if ((counter == 4'b1000) & (start_bit))				//Counter is 8? Then we set the start bit to 1. 
	begin
	start_bit <= 1'b0;
	counter <= 4'b0000;
	end

	if ((counter == 4'b1111) & (!start_bit) & (Bit < NBits))	//We make a loop (8 loops in this case) and we read all 8 bits
	begin
	Bit <= Bit+1;
	Read_data <= {Rx,Read_data[7:1]};
	counter <= 4'b0000;
	end
	
	if ((counter == 4'b1111) & (Bit == NBits)  & (Rx))		//Then we count to 16 once again and detect the stop bit (Rx input must be high)
	begin
	Bit <= 4'b0000;
	RxDone <= 1'b1;
	counter <= 4'b0000;
	start_bit <= 1'b1;						//We reset all values for next data input and set RxDone to high
	end
	end
	
	

end


////////////////////////////////////////////////////////////////////////////
//////////////////////////////Output assign/////////////////////////////////
////////////////////////////////////////////////////////////////////////////
/*Finally, we assign the Read_data register values to the RxData output and
that will be our final received value.*/
always @ (posedge Clk)
begin

if (NBits == 4'b1000)
begin
RxData[7:0] <= Read_data[7:0];	
end

if (NBits == 4'b0111)
begin
RxData[7:0] <= {1'b0,Read_data[7:1]};	
end

if (NBits == 4'b0110)
begin
RxData[7:0] <= {1'b0,1'b0,Read_data[7:2]};	
end
end




//End of the RX mdoule
endmodule


