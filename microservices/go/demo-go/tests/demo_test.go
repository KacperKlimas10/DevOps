package test

import "testing"

func TestSimpleDemo(t *testing.T) {
	value := 1
	if value != 1 {
		t.Errorf("Test failed!")
	}
}