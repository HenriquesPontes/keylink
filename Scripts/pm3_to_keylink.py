#!/usr/bin/env python3
import json
import sys
import struct
import argparse
import os

def parse_proxmark_dump(bin_file_path):
    """
    Parses a MIFARE Classic 1K .bin dump from Proxmark3.
    """
    try:
        with open(bin_file_path, 'rb') as f:
            data = f.read()
    except Exception as e:
        print(f"Error reading file: {e}")
        return None
        
    if len(data) != 1024 and len(data) != 4096:
        print(f"Warning: Unexpected file size {len(data)} bytes. Expected 1024 or 4096 for MIFARE Classic.")

    # Block 0 contains the manufacturer data (UID, ATQA, SAK)
    block0 = data[0:16]
    
    # Typically UID is 4 bytes for MIFARE Classic 1K
    uid = block0[0:4]
    uid_hex = uid.hex().upper()
    
    # Optional BCC (Byte 4)
    # ATQA and SAK are not always explicitly in standard bin dumps, but we can infer or extract them 
    # if we have the full Proxmark JSON dictionary. Since this script reads .bin, we'll hardcode 
    # the typical values for MIFARE Classic 1K. 
    # (Alternatively, you can read the .json output from hf mf dump if available)
    
    atqa = [0x04, 0x00] # Typical for 1K
    sak = 0x08          # Typical for 1K
    
    sectors = []
    num_sectors = 16 if len(data) == 1024 else 40
    
    for i in range(num_sectors):
        sector_data = []
        blocks_in_sector = 4 if i < 32 else 16
        
        for j in range(blocks_in_sector):
            block_idx = i * 4 + j if i < 32 else 128 + (i - 32) * 16 + j
            offset = block_idx * 16
            
            if offset + 16 <= len(data):
                block = data[offset:offset+16]
                sector_data.append(list(block))
            
        sectors.append(sector_data)

    card_data = {
        "uid": uid_hex,
        "atqa": atqa,
        "sak": sak,
        "sectors": sectors
    }
    
    return card_data

def main():
    parser = argparse.ArgumentParser(description="Convert Proxmark3 MIFARE Classic .bin dump to KeyLink JSON format.")
    parser.add_argument("input_bin", help="Path to the Proxmark3 .bin dump file")
    parser.add_argument("-o", "--output", help="Output JSON file path", default="keylink_card.json")
    
    args = parser.parse_args()
    
    print(f"Parsing {args.input_bin}...")
    card_data = parse_proxmark_dump(args.input_bin)
    
    if card_data:
        try:
            with open(args.output, 'w') as f:
                json.dump(card_data, f, indent=4)
            print(f"Success! Saved to {args.output}")
        except Exception as e:
            print(f"Error writing JSON: {e}")

if __name__ == "__main__":
    main()
