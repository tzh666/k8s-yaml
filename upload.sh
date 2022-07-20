#!/bin/bash
# 文件推送到git脚本
git add .

git commit -m $1

git branch -M main

git push -u origin main

# 更改远程分支后,强制让本地分支覆盖远程分支
# git push origin master -f