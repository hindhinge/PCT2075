--Rados³aw Sawicki
--253153
--PCT2075 component

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity PCT2075 is
	port( 	SDA: inout std_logic;
				TEMP: in std_logic_vector(15 downto 0); --Wejœcie okreœlaj¹ce zmierzon¹ temperaturê. TESTOWE TYLKO DO TESTBENCHA
				SCL : in std_logic; --Linia zegarowa
				A0 : in std_logic;	  --A0-A3 piny adresowe
				A1 : in std_logic;
				A2 : in std_logic;
				OS : out std_logic);	  --Overtemp Shutdown, wyjœcie sygnalizuj¹ce przekroczenie temperatury okreœlonej w rejestrze Tos (TODO)
end entity PCT2075;

architecture PCT2075_arch of PCT2075 is
--Przedrostki:
--s_ : stan
--reg_ :rejestr
--int_ : sygna³ wewnêtrzny
--pro_ : proces

type STATES is (s_IDLE,s_START,s_ADDR,s_ACKS,s_WRITE,s_SEND8,s_CONF8,s_ACKM, s_STOP); --Stany kompnentu odpowiadaj¹ kolejnym etapom transferu danych przez magistralê.
																													--IDLE: Linia I2C zwolniona, SDA = 1, SCL = 1
																													--START: Pocz¹tek transmisji, lub restart nastêpuj¹cy po komendzie zapisu: SDA 1->0, SCL = 1
																													--ADDR: Stan odczytu adresu od mastera, nastêpuje po START.
																													--WRITE: Bit zapisu, nastêpuje po bajcie adresu SDA = 0. Stan w którym nastepuje zapis do rejestru reg_Pointer.
																													--SEND8: Wys³anie 8 bitów danych przez termometr. Nastêpuje po restarcie.
																													--CONF8: Wys³anie 8 bitów przez mastera do urz¹dzenia oraz nadpisanie tymi danymi zawartoœci rejestru o adresie wskazanym w reg_Pointer.
																													--ACKS: Bit potwierdzenia urz¹dzenia w trybie slave. Wysy³any przez termometr po komendzie zapisu. SDA = 0 urz¹dzenie dzia³a poprawnie, SDA = 1 urz¹dzenie dzia³a niepoprawnie									--SEND8: Stan wysy³ania danych od d³ugoœci 8 bitów. 
																													--ACKM: Bit potwierdzenia urz¹dzenia w trybie master. Wysy³any przez Artyego po komendzie odczytu. SDA = 0 otrzymano dane, mo¿na wys³aæ kolejny bajt danych
																													--STOP: Oczekiwanie na bit stopu SDA: 0->1, SCL = 1
signal prev_state:STATES:=s_IDLE; --Obecny i poprzedni stan urz¹dzenia
signal state:STATES:= s_IDLE;

signal reg_Temp:std_logic_vector(15 downto 0) := "0000000000000000"; --Rejestr zawieraj¹cy zmierzon¹ temperaturê

signal reg_Conf:std_logic_vector(7 downto 0) := "00000000"; --Rejestr konfiguracyjny. B[7:5] Reserved. Startup = 000
																				--								  B[4:3] OS fault. Startup = 00 (OS queue = 1 [number of faults T>reg_Tos before OS output enable])
																				--								  B2 OS polarity. Startup = 0 (output active LOW)
																				--								  B1 OS operation mode. Startup = 0 (OS comparator mode)
																				--								  B0 Operation mode. Startup = 0 (Normal operation mode)

signal reg_Thyst:std_logic_vector(15 downto 0) := "0100101100000000"; --Startup = 75,0C. Rejestr histerezy

signal reg_Tos:std_logic_vector(15 downto 0) := "0101000000000000"; --Startup = 80,0C. Rejestr zawieraj¹cy limit temperatury, powy¿ej którego pojawia siê sygna³ na wyjœciu OS urz¹dzenia

signal reg_Tidle:std_logic_vector(7 downto 0) := "00000001"; --Rejestr okreœlaj¹cy co ile sekund nastêpuje pomiar temperatury. Domyœlnie 100ms. B[7:5] - Reserved
																				 -- 																											B[4:0] - Value * 100ms = sampling time

signal reg_Pointer:std_logic_vector(7 downto 0) := "00000000"; --Rejestr Pointer, nie mo¿e byæ odczytany. Przechowuje otrzyman¹ od mastera komendê.

signal int_inputdata:std_logic_vector(7 downto 0):= "00000000"; --Sygna³ wewnêtrzny przechowuj¹cy dane transmitowane od mastera do urz¹dzenia (adres,pointer,dane)

signal int_address:std_logic_vector(6 downto 0); --Rejestr przechowuj¹cy adres wys³any przez mastera w stanie s_ADDR

signal int_sdao:std_logic; --Sygna³ wewnêtrzny wyjœcia urz¹dzenia, ¿eby nie przypisywaæ bezpoœrednio do sygna³u wyjœciowego SDA_O

signal int_bitcounter:integer range 0 to 7; --Licznik odebranych/wys³anych bitów

signal int_regMSB: std_logic; --Sygna³ okreœlaj¹cy czy odczytujemy/zapisujemy starsz¹ czy m³odsz¹ czêœæ rejestrów 16 bitowych.

signal int_halfreg: std_logic_vector(7 downto 0):= "00000000"; --Rejestr na przechowywanie 8 bitów rejestrów 16 bitowych.

signal int_oe: std_logic := '0';

signal int_sdai: std_logic;


begin

pro_address:process(A0,A1,A2) --Proces przypisuj¹cy bie¿¹cy adres urz¹dzenia na podstawie wejœæ A0,A1 oraz A2.
	begin
	int_address <= "1001"&A0&A1&A2;
	end process pro_address;

pro_gettemp:process(TEMP) --PROCES DO TESTÓW. Symuluje odczyt temperatury przez urz¹dzenie
	begin
	reg_Temp <= TEMP;
	end process pro_gettemp;
	
pro_os:process(reg_Temp) --Jezeli odczytana temperatura wiêksza od ustawionej w rejestrze Tos to 1 na porcie OS.
	begin
		if(reg_Temp > reg_Tos) then
			OS <='1';
		else 
			OS <='0';
		end if;
	end process pro_os;
	
pro_oe:process(state) --Proces okreœlaj¹cy kiedy nale¿y za³¹czyæ output enable termometru
	begin
		if(state = s_SEND8) then
			int_oe <= '1';
		elsif (int_sdao = 'Z') then
			int_oe <= '0';
		end if;
	end process pro_oe;

pro_states:process(int_sdai,SCL) --Maszyna stanów, jedyny godny uwagi proces urz¹dzenia
	begin
	if(prev_state = s_IDLE and SDA = 'Z') then
		prev_state<=s_IDLE;
		state<=s_IDLE;
	elsif(state = s_IDLE and int_sdai'Event and int_sdai ='0' and SCL='1') then --Wykrywanie sygna³u start i restart. SDA 1 => 0 przy SCL = 1
		prev_state <= s_IDLE;
		state <= s_START;
	elsif(state = s_IDLE and int_sdai'Event and SCL='0' ) then --Wykrywanie braku restartu nastêpuj¹cego przy konfiguracji rejestrów (nie wiedzia³em jak to inaczej zrobiæ, wiêc po stanie WRITE 
																			  --musi nast¹piæ zmiana na linii SDA podczas gdy SCL = 0)
		prev_state <= s_IDLE;
		state <= s_CONF8;
		int_bitcounter <= 7;
		int_regMSB <= '1';
	elsif(state = s_STOP and int_sdai'Event and int_sdai ='1' and SCL='1') then --Przejœcie ze stanu STOP na IDLE po wykryciu SDA 0 => 1 przy SCL = 1
		prev_state <= s_STOP;
		state <= s_IDLE;
	elsif(SCL'Event) then --Spaghetti kodu opisuj¹ce przejœcia pomiêdzy pozosta³ymi stanami
		case state is
		
			when s_IDLE => -- Je¿eli brak aktywnoœci na linii SDA to urz¹dzenie pozostaje w stanie IDLE. Wyjœcia ze stanu IDLE opisane zosta³y powy¿ej
				if(int_sdai = '1' and SCL = '0') then
					int_sdao <= '1';
					prev_state <= s_IDLE;
					state <= s_IDLE;
				end if;
				
			when s_START => --Zmiana na linii SDA przy SCL = 0 oznacza pocz¹tek adresowania (zmiana nast¹pi zawsze bo sygna³ restartu zmienia SDA na 0, a ka¿dy adres zaczyna siê od 1) 
				int_bitcounter <= 7;
				if(SCL'Event and SCL ='0') then
					int_sdao <= '1';
					prev_state <= s_START;
					state <= s_ADDR;
				end if;
				
			when s_ADDR => --Zbocze narastaj¹ce SCL powoduje zapisanie danych z SDA do int_inputdata i dekrementacjê licznika bitów. Gdy licznik osi¹gnie zero przejœcie do stanu potwierdzenia ACKS
				if(SCL = '1' and SCL'Event) then
				int_inputdata(int_bitcounter) <= int_sdai;
					if(int_bitcounter > "000") then
						int_bitcounter <= int_bitcounter - 1;
						prev_state <= s_ADDR;
						state <= s_ADDR;
					else
						prev_state <= s_ADDR;
						state<= s_ACKS;
					end if;
				end if;
				
			when s_ACKS =>
				if (prev_state = s_ADDR) then --Je¿eli poprzednim stanem by³o adresowanie sprawdzamy poprawnoœæ adresu. Jeœli poprawny potwierdzamy przez SDA = 0, je¿eli niepoprawny SDA = 1
					if(int_inputdata(7 downto 1) = int_address and SCL'EVENT) then
						int_sdao <= '0';
					else 
						int_sdao <= '1';
					end if;
					
					if(int_inputdata(0) = '1' and SCL'Event and SCL ='1') then --Ósmy bit adresu jest bitem R/W od którego zale¿y jak¹ akcjê chcemy wykonaæ
						prev_state <= s_ACKS;
						state <= s_SEND8;
						int_bitcounter <= 7;
						int_inputdata <= "00000000";
						int_regMSB <= '1';

					elsif(int_inputdata(0) = '0' and SCL'Event and SCL ='1') then 
						prev_state <= s_ACKS;
						state <= s_WRITE;
						int_bitcounter <= 7;
						int_inputdata <= "00000000";
					end if;
					
					
				
				elsif(prev_state = s_WRITE) then --Je¿eli poprzednio zapisywaliœmy do reg_Pointer to nastêpuje sprawdzenie czy przes³ane zosta³o 8 bitów.
															--Jeœli tak to SDA = 0, jeœli nie to SDA = 1. Nastêpnie przejœcie do stanu IDLE i oczekiwanie na RESTART lub dane konfiguracji CONF8
					if(int_bitcounter = "0" and SCL'Event and SCL ='0') then
						prev_state <= s_ACKS;
						int_sdao <= '0';
						reg_Pointer <= int_inputdata;
						int_inputdata <= "00000000";						
						state <= s_IDLE;
					elsif(int_bitcounter > "0" and SCL'Event and SCL ='0') then
						prev_state <= s_ACKS;
						int_sdao <= '1';
						reg_Pointer <= int_inputdata;
						int_inputdata <= "00000000";						
						state <= s_IDLE;
					end if;
					
				elsif(prev_state = s_CONF8) then --Je¿eli poprzednim stanem by³a konfiguracja rejestrów i przes³ano osiem bitów SDA = 0. W przeciwnym wypadku SDA = 1
					if(int_bitcounter = "0" and SCL'Event and SCL ='1') then
						int_sdao <= '0';
						int_inputdata <="00000000";
						int_bitcounter <= 7;
						if(int_regMSB = '1') then --Zapisany zosta³ starszy bajt rejestru, przejœcie do stanu STOP je¿eli rejestr ma 8 bitów, lub ponownie do stanu CONF8 je¿eli rejestr ma 16 bitów
							if(reg_Pointer = "00000001") then --000 reg_Temp (tylko do odczytu), 001 reg_Conf, 010 reg_Thyst, 011 reg_Tos, 101 reg_Tidle
								reg_Conf <= int_inputdata;
								prev_state <= s_ACKS;
								state <= s_STOP;
							end if;
							if(reg_Pointer = "00000101") then
								reg_Tidle <= int_inputdata;
								prev_state <= s_ACKS;
								state <= s_STOP;
							end if;
							if(reg_Pointer = "00000010") then
								reg_Thyst(15 downto 8) <= int_inputdata;
								int_regMSB <= '0';
								prev_state <= s_ACKS;
								state <= s_CONF8;
							end if;
							if(reg_Pointer = "00000011") then
								reg_Tos(15 downto 8) <= int_inputdata;
								int_regMSB <= '0';
								prev_state <= s_ACKS;
								state <= s_CONF8;
							end if;
						elsif (int_regMSB ='0') then --Zapisany zosta³ m³odszy bajt rejestru 16 bitowego, przejœcie do stanu STOP.
							if(reg_Pointer = "00000010") then
								reg_Thyst(7 downto 0) <= int_inputdata;
								int_regMSB <= '1';
								prev_state <= s_ACKS;
								state <= s_STOP;
							end if;
							if(reg_Pointer = "00000011") then
								reg_Tos(7 downto 0) <= int_inputdata;
								int_regMSB <= '1';
								prev_state <= s_ACKS;
								state <= s_STOP;
							end if;
						end if;
					elsif(int_bitcounter > "0" and SCL'Event and SCL ='0') then --Przes³ane zosta³o mniej ni¿ 8 bitów,zg³oszenie b³êdu przez SDA = 1. 
						int_sdao <= '1';
						int_inputdata <="00000000";
						int_bitcounter <= 7;
						if(int_regMSB ='1') then --Je¿eli b³¹d wyst¹pi³ przy zapisie starszego bajtu rejestru SDA = 0
							if(reg_Pointer = "00000001" or reg_Pointer = "00000101") then --Je¿eli rejestr jest 8 bitowy przechodzimy do stanu bezczynnoœci
								prev_state <= s_ACKS;
								state <= s_IDLE;
							elsif(reg_Pointer = "00000010" or reg_Pointer = "00000011") then --Je¿eli rejestr jest 16 bitowy odczytjemy m³odszy bit
								prev_state <= s_ACKS;
								state <= s_CONF8;
							end if;
						elsif(int_regMSB ='0') then
							prev_state <= s_ACKS; --Je¿eli b³¹d wyst¹pi³ przy zapisie m³odszego bajtu 16 bitowego rejestru SDA = 0 i przejœcie do stanu bezczynnoœci
							state <= s_IDLE;
						end if;
					end if;
				end if;
		
			when s_WRITE => --Zbocze narastaj¹ce SCL powoduje zapis wartoœci linii SDA do int_inputdata i dekrementacjê int_bitcounter
				int_sdao <= '1';
				if(SCL = '1' and SCL'Event) then
					int_inputdata(int_bitcounter) <= int_sdai;
					if(int_bitcounter > "000") then --Jeœli odebrano <8 bitów to wracamy z powrotem do stanu WRITE
						int_bitcounter <= int_bitcounter - 1;
						prev_state <= s_WRITE;
						state <= s_WRITE;
					elsif (int_bitcounter = "0") then --Jeœli odebrano 8 bitów to przejœcie do stanu potwierdzenia ACKS
						prev_state <= s_WRITE;
						state<= s_ACKS;
					end if;
				end if;
				
			when s_SEND8 => --Stan wysy³ania zawartoœci rejestru
				if(reg_Pointer = "00000000") then --Je¿eli wysy³amy zawartoœæ reg_Temp
					if (int_regMSB ='1')then --Je¿eli wysy³amy starszy bajt to int_halfreg przyjmuje wartoœæ starszych 8 bitów, w przeciwnym przypadku m³odszych
						int_halfreg <= reg_Temp(15 downto 8);
					else
						int_halfreg <= reg_Temp(7 downto 0);
					end if;
					if(SCL'Event and SCL = '1') then --Narastaj¹ce zbocze SCL powoduje wys³anie bitu na SDA oraz dekrementacjê int_bitcounter 
						int_sdao <= int_halfreg(int_bitcounter);
						if(int_bitcounter > "000") then --Je¿eli wys³ano mniej ni¿ 8 bitów to powrót do stanu SEND8
							int_bitcounter <= int_bitcounter - 1;
							prev_state <= s_SEND8;
							state <= s_SEND8;
						else --Je¿eli wys³ano 8 bitów to wys³anie potwierdzenia ACKS
							prev_state <= s_SEND8;
							state <= s_ACKM;
						end if;
					end if;
				end if;
				
				if(reg_Pointer = "00000001") then --To samo co powy¿ej tylko dla rejestru reg_Conf
					if(SCL'Event and SCL = '1') then
						int_sdao <= reg_Conf(int_bitcounter);
						if(int_bitcounter > "000") then
							int_bitcounter <= int_bitcounter - 1;
							prev_state <= s_SEND8;
							state <= s_SEND8;
						else
							prev_state <= s_SEND8;
							state <= s_ACKM;
						end if;
					end if;
				end if;
				
				if(reg_Pointer = "00000010") then --To samo co powy¿ej tylko dla rejestru reg_Thyst
					if (int_regMSB ='1')then
						int_halfreg <= reg_Thyst(15 downto 8);
					else
						int_halfreg <= reg_Thyst(7 downto 0);
					end if;
					if(SCL'Event and SCL = '1') then
						int_sdao <= int_halfreg(int_bitcounter);
						if(int_bitcounter > "000") then
							int_bitcounter <= int_bitcounter - 1;
							prev_state <= s_SEND8;
							state <= s_SEND8;
						else
							prev_state <= s_SEND8;
							state <= s_ACKM;
						end if;
					end if;
				end if;
				
				if(reg_Pointer = "00000011") then --To samo co powy¿ej tylko dla rejestru reg_Tos
					if (int_regMSB ='1')then
						int_halfreg <= reg_Tos(15 downto 8);
					else
						int_halfreg <= reg_Tos(7 downto 0);
					end if;
					if(SCL'Event and SCL = '1') then
						int_sdao <= int_halfreg(int_bitcounter);
						if(int_bitcounter > "000") then
							int_bitcounter <= int_bitcounter - 1;
							prev_state <= s_SEND8;
							state <= s_SEND8;
						else
							prev_state <= s_SEND8;
							state <= s_ACKM;
						end if;
					end if;
				end if;
				
				if(reg_Pointer = "00000101") then --To samo co powy¿ej tylko dla rejestru reg_Tidle
					if(SCL'Event and SCL = '1') then
						int_sdao <= reg_Tidle(int_bitcounter);
						if(int_bitcounter > "000") then
							int_bitcounter <= int_bitcounter - 1;
							prev_state <= s_SEND8;
							state <= s_SEND8;
						else
							prev_state <= s_SEND8;
							state <= s_ACKM;
						end if;
					end if;
				end if;
				
			when s_CONF8 => --Stan odczytywania danych do konfiguracji rejestrów
				int_sdao <= '1';
				if(SCL = '1' and SCL'Event) then --Zbocze narastaj¹ce SCL powoduje zapis wartoœci linii SDA do int_inputdata i dekrementacje int_bitcounter
					int_inputdata(int_bitcounter) <= int_sdai;
					if(int_bitcounter > "000") then --Je¿eli odebrano mniej ni¿ 8 bitów to powrót do stanu CONF8
						int_bitcounter <= int_bitcounter - 1;
						prev_state <= s_CONF8;
						state <= s_CONF8;
					elsif(int_bitcounter = "0") then --Je¿eli odebrano 8 bitów to wys³anie potwierdzenia ACKS
						prev_state <=s_CONF8;
						state <= s_ACKS;
					end if;
				end if;
			
			when s_ACKM => --Stan oczekiwania na potiwerdzenie odebrania danych przez mastera
				int_sdao <= 'Z';
				if(SCL'Event and SCL ='1') then
					if(int_regMSB = '0' or reg_Pointer = "00000001" or reg_Pointer = "00000101") then --Je¿eli wysy³ano dane z rejestru 8 bitowego po jednym takcie zegara przejœcie do stanu oczekiwania na sygna³ STOP
						prev_state <= s_ACKM;
						state <= s_STOP;
					else --Je¿eli wysy³ano starszy bajt z rejestru 16 bitowego nastêpuje zmiana int_regMSB na 0 i przejœcie do SEND8 aby przes³aæ m³odszy bajt danych tego rejestru
						int_regMSB <='0';
						int_bitcounter <= 7;
						prev_state <= s_ACKM;
						state <= s_SEND8;
					end if;
				end if;
				
			when s_STOP => --Oczekiwanie na sygna³ STOP (przejœcie STOP => IDLE na samej górze procesu) i zerowanie rejestrów wewnêtrznych
				int_sdao <='1';
				int_bitcounter <= 7;
				reg_Pointer <= "00000000";
				state <= s_STOP;
				
			when others =>
				state <= s_IDLE;
		end case;
	end if;
	end process pro_states;



SDA <= int_sdao when int_oe = '1' else 'Z';
int_sdai <= SDA when int_oe = '0';

end architecture PCT2075_arch;

