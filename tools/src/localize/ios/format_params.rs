/// Count format parameters (%@, %d, %lld, etc.) but not %%.
pub fn count_format_parameters(s: &str) -> usize {
    let mut count = 0;
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '%' {
            match chars.peek() {
                Some('%') => {
                    chars.next(); // skip %%
                }
                Some(_) => count += 1,
                None => {}
            }
        }
    }
    count
}
