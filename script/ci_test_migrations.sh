#!/bin/bash

set -e

if [ -z "$CI" ]
then
    GIT_QUIET='-q'
    PIP_QUIET='-qqq'
    DBMIGRATOR_QUIET='--quiet'
else
    GIT_QUIET=''
    PIP_QUIET=''
    DBMIGRATOR_QUIET=''
fi

git fetch $GIT_QUIET origin master
first_commit=$(git log --format='%h' --reverse FETCH_HEAD.. | head -1)

# keep track of which branch we are on, so we can go back to it later
if [ -z "$CI" ]
then
    current_commit=$(git symbolic-ref --short HEAD)
else
    current_commit=$(git log --format='%h' | head -1)
fi

if [ -z "$first_commit" ]
then
    echo Nothing to check.
    exit
fi

# checkout the branch point
git checkout $GIT_QUIET $first_commit^
pip uninstall -y cnx-db
pip install $PIP_QUIET .

# install db-migrator and cnx-db
pip install $PIP_QUIET 'db-migrator>=1.0.0'

export DB_URL='postgresql://tester:tester@localhost:5432/testing'

# set up the database
dropdb -U postgres testing
createdb -U postgres -O tester testing
cnx-db init
dbmigrator $DBMIGRATOR_QUIET --db-connection-string="$DB_URL" init

# store the schema
pg_dump -s 'dbname=testing user=tester' >old_schema.sql

# go back to the branch HEAD
git checkout $GIT_QUIET $current_commit
pip uninstall -y cnx-db
pip install $PIP_QUIET .

# mark all the repeat, deferred migrations as not applied (to make the
# calculation of the number of migrations to rollback easier)
dbmigrator $DBMIGRATOR_QUIET --db-connection-string="$DB_URL" list | \
    awk '/deferred\*/ {print $1}' | \
    while read timestamp; do dbmigrator $DBMIGRATOR_QUIET --db-connection-string="$DB_URL" mark -f $timestamp; done

# check the number of migrations that are going to run
applied_before=$(dbmigrator $DBMIGRATOR_QUIET --db-connection-string="$DB_URL" list | awk 'NF>3 {applied+=1}; END {print applied}')

# run the migrations
dbmigrator $DBMIGRATOR_QUIET --db-connection-string="$DB_URL" migrate --run-deferred

applied_after=$(dbmigrator $DBMIGRATOR_QUIET --db-connection-string="$DB_URL" list | awk 'NF>3 {applied+=1}; END {print applied}')
steps=$((applied_after-applied_before))

# store the schema
pg_dump -s "$DB_URL" >migrated_schema.sql

# rollback the migrations
if [ "$steps" -gt 0 ]
then
    dbmigrator $DBMIGRATOR_QUIET --db-connection-string="$DB_URL" rollback --steps=$steps
fi

pg_dump -s "$DB_URL" >rolled_back_schema.sql

# reset database
dropdb -U postgres testing
createdb -U postgres -O tester testing
cnx-db init
dbmigrator $DBMIGRATOR_QUIET --db-connection-string="$DB_URL" init

pg_dump -s "$DB_URL" >new_schema.sql

# Put dev environment back, if not on Travis
if [ -z "$CI" ]
then
    pip install $PIP_QUIET -e .
fi

# check schema
rollback=$(diff -wu old_schema.sql rolled_back_schema.sql || true)
migration=$(diff -wu new_schema.sql migrated_schema.sql || true)

if [ -n "$rollback" ]
then
    echo "Rollback test failed:"
    diff -wu old_schema.sql rolled_back_schema.sql || true
fi

if [ -n "$migration" ]
then
    echo "Migration test failed:"
    diff -wu new_schema.sql migrated_schema.sql || true
fi

if [ -z "$rollback" -a -z "$migration" ]
then
    echo "Migration and rollback tests passed."
    exit 0
fi

exit 1
