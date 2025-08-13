-- test_kitty.lua (v2 - Corrected)
-- A simple Lua script to test the Kitty graphics protocol in a compatible terminal.
-- This version uses a pre-encoded Base64 string to avoid runtime errors.

-- This is the Base64-encoded string for a tiny 1x1 pixel red PNG image.
local image_data_base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4X2P4z8AAAAMBAAG/ztajAAAAAElFTkSuQmCC"

-- The Kitty graphics protocol works by sending special escape codes.
-- The format is: \x1b_G<key>=<value>,<key>=<value>...;<payload>\x1b\\
-- \x1b is the escape character (ASCII 27).
-- _G indicates a graphics operation.
-- a=T means the Action is to Transmit and display.
-- f=100 means the Format is PNG (100).
-- The payload is the Base64 encoded image data.
-- \x1b\\ is the "end of transmission" code.

-- We need to send the data in chunks, as terminals have a limit on the
-- size of a single write. 4096 bytes is a safe chunk size.
local chunk_size = 4096
local transmitted = 0

-- Start the transmission using the control code.
-- We set m=1 to indicate that more data chunks will follow.
io.write(string.format("\x1b_Gf=100,a=T,m=1;"))

-- Send the Base64 payload in one or more chunks.
while transmitted < #image_data_base64 do
	local chunk = image_data_base64:sub(transmitted + 1, transmitted + chunk_size)
	io.write(chunk)
	transmitted = transmitted + #chunk

	-- If we haven't sent everything yet, send another control code
	-- to let the terminal know more is coming.
	if transmitted < #image_data_base64 then
		io.write("\x1b_Gm=1;")
	end
end

-- End the transmission with m=0 and the final escape sequence.
io.write("\x1b_Gm=0;\x1b\\")

io.flush() -- Ensure all data is written to the terminal

print("\n\nKitty graphics test complete.")
print("If you see a small red square just above this text, the test was successful!")
