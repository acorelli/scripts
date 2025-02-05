[![](https://www.acorelli.com/scripts.jpg)](https://github.com/acorelli/scripts)  
  
# Scripts and Stuff  

**Name** | **Description**  
:--- | :---    
`clean_branches.ps1` | This PowerShell script is designed to clean up local Git branches that have been merged or are no longer needed, helping to maintain a tidy repository.  
`get_reviewers.ps1` | Selects a asignee/reviewer at random from a list of developer names.
`get_token.ps1` | Retrieves an authentication token, possibly from a service like GitLab or Jira, to authenticate API requests in other scripts or tools. Requires a current token to use.
`jira_sprint_query.ps1` | Queries Jira to retrieve information about the current sprint number.
`merge_no_jenkins.ps1` | Performs a Git merge operation without triggering Jenkins build jobs, useful when changes don't require immediate continuous integration processes.
`merge_request_tool.ps1` | Assists in creating or managing merge requests, automating the submission process & fetching details of from corresponding Jira tickets.
`rename.bat` | A batch script to rename files or directories based on predefined patterns or rules, streamlining bulk renaming tasks.
`restore_names.bat` | Reverts the changes made by rename.bat, restoring original file or directory names to maintain consistency.
`updateHosts.ps1` | Updates the repo's hosts via regex replace
`updateRemotes.ps1` | Updates Git remote URLs, which is beneficial when repositories are migrated or when access methods change.
`update_repo.ps1` | Helper to automate the `version_update_tool`
`version_update_tool.ps1` | Manages version updates, updating CMakeLists in [`♠ SPADES`](https://gitlab.com/acorelli/tools/spades) templated projects to match your current Jira sprint number