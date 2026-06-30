struct Point { x: i32, y: i32 }
enum Dir { N, S }
trait Greet { fn hello(&self); }
impl Greet for Point { fn hello(&self) {} }
mod inner { pub fn helper() {} }
fn alpha(a: i32, b: i32) -> i32 { a + b }
