# JIRA synchronization tool

> This is specific JIRA ServiceDesk <-> JIRA Core synchronization utility

Are you vendor using JIRA ServiceDesk and your customer with own JIRA Core/Software? Then this is tool to automatize synchronization issues with transitions, comments, worklogs and file attachments between two system. Your customer no longer need to login thru servicedesk to your JIRA.

## How it works and JIRA system prerequisites

**Your/Vendor JIRA ServiceDesk setup**
- You have ServiceDesk setup
- You have one servicedesk account to submit and modify issues in ServiceDesk project
- You have separate project for Customer project
- Your ServiceDesk workflow is compatible with [servicedesk_workflow.xml](docs/servicedesk_workflow.xml)
- Your vendor project workflow is compatible with [vendor_workflow.xml](docs/vendor_workflow.xml)

**Your Customer JiRA Core/Software setup**
- You have one account with access to customers JIRA
- Customer have one separate project created to assing you issues
- Customers project workflow is compatible with [customer_workflow.xml](docs/customer_workflow.xml)

**How the synchronizations works**
- Your customer is creating new issues and bugreports directly in own JIRA
- When issue changed status from "Draft" to "To Plan", is synchronized to vendors ServiceDesk
- In ServiceDesk you can create more depending tasks in "Customer project" (link type "FF depends on")
- Every depending task is synchronized to customers project issues as sub-tasks
- Every transition is synchronized between projects (In Progress, Resolved, Done,...)

## How to start

- copy config.json.example to config.json and configure
- create database tables defined in mysql.sql
- run ./jira_sync.pl

## Support

You can contact open@comsultia.com with questions or request to commercial integration/support