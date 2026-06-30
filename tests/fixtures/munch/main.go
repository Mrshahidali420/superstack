package main
type Shape interface { Area() float64 }
type Circle struct { r float64 }
func (c Circle) Area() float64 { return 3.14 }
func Alpha(a int, b int) int { return a + b }
