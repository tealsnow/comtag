use anyhow::Result;
use clap::{arg, Command};
use regex::Regex;
use std::{io::Read, path::Path};

fn main() -> Result<()> {
    let matches = Command::new("comtag")
        .arg(arg!(--file <FILE>))
        .get_matches();

    let file = matches.value_of("file").unwrap();

    // @FIXME: Fix this, very broken
    let src = read_file(file)?;

    let lines = src.lines();

    let tags: Vec<Tag> = lines
        .enumerate()
        .map(|(line_i, line)| {
            line.trim()
                .strip_prefix("//")
                .map(|comment| {
                    comment
                        .trim()
                        .strip_prefix('@')
                        .map(|tag_line| {
                            let tag_re = Regex::new(r"^\S[^:\n]+").unwrap(); // https://regexr.com/6hqsp

                            tag_re.find(tag_line).map(|tag_match| {
                                let mut tag_name = tag_match.as_str();

                                let name_re = Regex::new(r"\(.+\)").unwrap();

                                let name = name_re.find(tag_name).map(|name| {
                                    tag_name = &tag_name[..name.start()];
                                    let name = name.as_str();
                                    name[1..name.len() - 1].to_string()
                                });

                                let message = tag_line[tag_match.end()..]
                                    .strip_prefix(':')
                                    .map(|message| message.trim().to_string());

                                Tag {
                                    line: line_i,
                                    tag: tag_name.to_string(),
                                    name,
                                    message,
                                }
                            })
                        })
                        .flatten()
                })
                .flatten()
        })
        .flatten()
        .collect::<_>();

    tags.iter().for_each(|tag| {
        print!("{}: {}", tag.line + 1, tag.tag);
        if let Some(name) = &tag.name {
            print!("({})", name);
        }
        if let Some(msg) = &tag.message {
            print!("\t{}", msg);
        }
        println!()
    });

    // @ not tag : stuff

    // @SPEED
    // @XXX(Ketan Reynolds): bad
    // @TODO

    Ok(())
}

#[derive(Debug)]
struct Tag {
    line: usize, // 0 based
    tag: String,
    name: Option<String>,
    message: Option<String>,
}

fn read_file<T: AsRef<Path>>(path: T) -> std::io::Result<String> {
    let mut file = std::fs::File::open(path)?;
    let mut string = String::new();
    let _ = file.read_to_string(&mut string)?;
    Ok(string)
}
