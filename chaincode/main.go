package main

import (
	"fmt"
	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

type MedicalRecordContract struct {
	contractapi.Contract
}

func (c *MedicalRecordContract) InitLedger(ctx contractapi.TransactionContextInterface) error {
	fmt.Println("EHR Chaincode Ledger Initialized")
	return nil
}

func main() {
	cc, err := contractapi.NewChaincode(&MedicalRecordContract{})
	if err != nil {
		panic(err.Error())
	}
	if err := cc.Start(); err != nil {
		panic(err.Error())
	}
}
