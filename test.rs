fn main() {
    let s = r#"rift-cli subscribe cli --event windows_changed --command sh --args -c --args 'osascript -e " tell application \"System Events\" to     if (get name of every process) contains \"AeroSpaceBar\" then         tell application \"AeroSpaceBar\" to «event ascrpsbr» \"updateOnFocusChanged\" "'"#;
    // We can't easily download shell_words. Let's just use python, wait, python's shlex acts differently from rust's shell_words?
    // Actually, I can just use a bash command to test shlex in rust.
}