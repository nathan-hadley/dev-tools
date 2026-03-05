# --------- General aliases ---------

alias cursor="open -a Cursor"
alias edit="cursor ~/.zshrc"
alias save="source ~/.zshrc"
alias cd="z" # requires zoxide to be installed and initialized in .zshrc


# --------- Git helpers ---------

commitpush(){
  git add .
  git commit -m "$1"
  git push
}

commit(){
  git commit -m "$1"
}

alias gs="git status"
alias add="git add -p"
alias co="git checkout"
alias cr="git !sh -c 'git checkout -b CR origin/$1' -"
alias br="git branch"
alias pull="git pull"
alias push="git push"
alias stash="git stash"
alias unstash="git stash apply"
alias delete="git branch --delete"

source ~/dev/dev-tools/scripts/wtree.sh
source ~/dev/dev-tools/scripts/wtmerge.sh

# Synchronize with remote and remove local branches whose upstream was deleted
cleanBranches(){
  git pull --prune
  git branch --format '%(refname:short) %(upstream:track)' | awk '$2 == "[gone]" { print $1 }' | xargs -r git branch -D
}
alias clean="cleanBranches"

# Undo last commit if not pushed
alias undo="git reset HEAD~1 --mixed"

alias history="git log --oneline --graph --decorate"


# --------- GitHub review & weekly report helpers ---------

alias weekly="~/dev/dev-tools/scripts/gh-weekly-prs.sh"
alias reviews='gh search prs --review-requested=@me --state=open --json author,url --jq ".[] | \"\\(.author.login): \\(.url)\""'


# --------- Docker helpers ---------

alias prune-docker="docker system prune -a -f --volumes"
alias dc="docker compose"

# --------- Node / JS helpers ---------

alias rmrf='rm -rf .parcel-cache dist node_modules'


# --------- Android helpers ---------

alias scrcpy='scrcpy --serial R5CX81AD2CP'