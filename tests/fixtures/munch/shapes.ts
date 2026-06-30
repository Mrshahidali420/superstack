interface Shape { area(): number; }
type ID = string | number;
enum Color { Red, Green }
export function area(s: Shape): number { return s.area(); }
const make = (n: number): ID => `${n}`;
class Circle implements Shape { area() { return 3.14; } }
