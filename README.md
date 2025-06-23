# close-issue-as-duplicate

Small script to close an issue as duplicate

## How to install

- [Install with UBI](https://github.com/houseabsolute/ubi?tab=readme-ov-file#how-to-use-it )
- Install with [Mise](https://mise.jdx.dev/): `mise use -g ubi:ekroon/close-issue-as-duplicate`

## Usage

Run without argument to get description: `close-issue-as-duplicate`:

```
Usage: ./close-issue-as-duplicate.sh <issue_to_close> [duplicate_of_issue]
Format: org/repo#<issue_number> [org/repo#<issue_number>]
Example: ./close-issue-as-duplicate.sh octocat/Hello-World#42 octocat/Hello-World#15
Example: ./close-issue-as-duplicate.sh octocat/Hello-World#42
```
