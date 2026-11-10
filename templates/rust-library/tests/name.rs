//! Public-API behavior of [`template_library::Name`].

use template_library::Name;

#[test]
fn trims_surrounding_whitespace() {
    let name: Name = "\t Ferris \n".parse().expect("non-empty input parses");
    assert_eq!(name.as_str(), "Ferris", "input {:?}", "\t Ferris \n");
}

#[test]
fn rejects_blank_input() {
    for input in ["", "   ", "\n\t"] {
        assert!(
            input.parse::<Name>().is_err(),
            "blank input {input:?} must not parse"
        );
    }
}
