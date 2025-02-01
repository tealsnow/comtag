<div align="center">
  <h1>comtag<h1>

  <p>
    <strong>@TODO: write a proper README</strong>
  </p>
</div>

## About

This is a little cli program to find a list all **com**ment-**tag**s within a set of files and present them in an easily readable manor.
Simular to the todo tool within jetbrains editors. A list of files and their 'todo's
This is a little more general.

## Syntax

The general syntax is as such:
```
'begin of comment' '@' tag_name ( '(' author ')' )? ( ':' comment_text )?
```

> [!NOTE]
> Configuration of the what to consider to be the begining of a comment has not been implement as of yet. 
> When done the abiliy to associate comment strings to file types will be available in a config file.

> [!IMPORTANT]
> Support for "mulitline" comments is not implmented and probably wont be.
> So syntax like `/* @TAG */` and `<!-- @TAG -->` will not work

### Examples

```
// @HACK
# @TODO: implement this thing one day
-- @FIXME(ketanr)
@NOTE(ketanr): This does it that way because I said so

@NOTE: We can also continue the comment/tag text on the next line
 as long as it starts after the column the '@' is found in

 and there is nothing between (this will not be a part of the above @NOTE)

@What_Ever_You_Want: as long as it is after the '@'
                     it will be considered a part of the tag

// @NOTE: it does not work if the actual comment does not start on the same column
       // such as like this

```

## Screenshots

```
@TODO: include some screenshots
       (this one is not a joke)
```
