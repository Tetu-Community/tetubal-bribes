.PHONY: contracts

default: all

contracts:
	forge fmt && forge test

all: contracts
