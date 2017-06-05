#!/usr/bin/perl
use utf8;
use open ':utf8', ':std';
use strict;
use lib 'libs';

use JIRA::REST;
use DateTime;
use Data::Dumper;
use DBI;
use JSON;

our %arg;

our $config;
do {
	local $/;
	open( my $fh, '<', 'config.json' );
	$config = decode_json( <$fh> );
};

my $customer=$config->{'customer'}->{'name'};
	my $customer_url=$config->{'customer'}->{'url'};
	my $customer_user=$config->{'customer'}->{'user'};
	my $customer_project=$config->{'customer'}->{'project'};
	my $customer_key=$config->{'customer'}->{'key'};
	my $customer_account=$config->{'customer'}->{'account'};
	my $customer_self=$config->{'customer'}->{'self'};
	my $customer_email_match=$config->{'customer'}->{'email_match'};
my $vendor=$config->{'vendor'}->{'name'};
	my $vendor_url=$config->{'vendor'}->{'url'};
	my $vendor_user=$config->{'vendor'}->{'user'};
	my $vendor_project=$config->{'vendor'}->{'project'};
	my $vendor_key=$config->{'vendor'}->{'key'};
	my $vendor_sub_issue_type=$config->{'vendor'}->{'sub_issue_type'}; # FF-depends-on
	my $vendor_sub_project=$config->{'vendor'}->{'sub_project'};
	my $vendor_sub_key=$config->{'vendor'}->{'sub_key'};
	my $vendor_self=$config->{'vendor'}->{'self'};
	my $vendor_email_match=$config->{'vendor'}->{'email_match'};

my $jira_customer = JIRA::REST->new($customer_url, $vendor_user, $config->{'vendor'}->{'password'});
my $jira_vendor = JIRA::REST->new($vendor_url, $customer_user, $config->{'customer'}->{'password'});
my $jira_vendor_servicedesk = JIRA::REST->new($vendor_url, $customer_user, $config->{'customer'}->{'password'},{
	'host' => $vendor_url.'/rest/servicedeskapi'
});


#my $out=$jira_vendor->POST('/issueLink', undef, {
#	"type" => {  "name" => "Including" },
#	"inwardIssue" => { "key" => 'SLA-25' },
#	"outwardIssue" => { "key" => 'MUZ-2' }
#});
#print Dumper($out);
#exit;

my $dsn = $config->{'database'}->{'dsn'};
my $dbh = DBI->connect($dsn, $config->{'database'}->{'user'}, $config->{'database'}->{'password'});
our $synced;

our %conversion;
do {
	local $/;
	open( my $fh, '<', 'transitions.json' );
	%conversion = %{decode_json( <$fh> )};
};

my $dt=DateTime->now('time_zone' => 'local');

open(HND,'<jira_sync.datetime');
my $datetime_customer_from = <HND> || $dt->strftime('%FT%T');
	chomp($datetime_customer_from);
my $datetime_vendor_from = <HND> || $dt->strftime('%FT%T');
	chomp($datetime_vendor_from);
close(HND);

my $datetime_customer_max = $datetime_customer_from;
my $datetime_vendor_max = $datetime_vendor_from;

#	chomp($datetime_from);
	$datetime_customer_from=~s|T| |;
	$datetime_customer_from=~s|:\d\d\..*$||;
	$datetime_customer_from=~s|(\d\d):(\d\d):\d\d$|$1:$2|;
	$datetime_vendor_from=~s|T| |;
	$datetime_vendor_from=~s|:\d\d\..*$||;
	$datetime_vendor_from=~s|(\d\d):(\d\d):\d\d$|$1:$2|;
	
print "checking changes from '$datetime_customer_from' and '$datetime_vendor_from'\n"
	unless $arg{'key'};

my $query_customer='AND updated >= "'.$datetime_customer_from.'" ';
my $query_vendor='AND updated >= "'.$datetime_vendor_from.'" ';

use param;

my $search_customer_do=1;
my $search_vendor_do=1;
if ($arg{'force'})
{
	$query_customer='';
	$query_vendor='';
}
if ($arg{'key'}=~/^$customer_key\-/)
{
	print "request for '$arg{'key'}'\n";
	$search_vendor_do=0;
	$query_customer = 'AND key='.$arg{'key'}.' ';
}
elsif ($arg{'key'}=~/^$vendor_key\-/ || $arg{'key'}=~/^$vendor_sub_key\-/)
{
	print "request for '$arg{'key'}'\n";
	$search_customer_do=0;
	$query_vendor = 'AND key='.$arg{'key'}.' ';
}
elsif ($arg{'key'} && $config->{'customer'}->{'multiproject'})
{
	print "request for '$arg{'key'}'\n";
	$search_vendor_do=0;
	$query_customer = 'AND key='.$arg{'key'}.' ';
}
elsif ($arg{'key'})
{
	print "can't search for this issue key\n";
	exit;
}

if (!$config->{'customer'}->{'multiproject'})
{
	$query_customer.='AND project in ('.$customer_project.') ';
}

# vendor -> customer
#

=head1
my $out=$jira_vendor->GET('/issue/SLA-8677/properties/feedback.token.key');
#my $out=$jira_vendor->GET('/issue/SLA-8677/properties/request.channel.type');
my $out=$jira_vendor->PUT('/issue/SLA-8677/properties/feedback.token.key', undef, '9e253c1dabaf291c0f77a8c6f66475462391b52e');	

#my $out=$jira_vendor->PUT('/issue/SLA-8677/properties/request.channel.type', undef, 'jira');	

#my $out=$jira_vendor->PUT('/issue/SLA-8677/properties/feedback', undef,{
#	'token' => {
#		'key' => '9e253c1dabaf291c0f77a8c6f66475462391b52e'
#	}
#});

# http://jira.comsultia.com/servicedesk/customer/portal/3/SLA-8689/feedback?token=9e253c1dabaf291c0f77a8c6f66475462391b52e&rating=5
print Dumper($out);
exit;
=cut

my @issues;
if ($search_customer_do)
{
	print "search customer '$query_customer'\n";
	my $jql = '(reporter = '.$vendor_user.' OR assignee = '.$vendor_user.' OR Contributors in ('.$vendor_user.') ) ' # assigned to vendor
#		.'AND issuetype in standardIssueTypes() '
		.'AND (status not in (Draft) OR reporter = '.$vendor_user.' ) ' # ignore drafts
#		.'AND project in ('.$customer_project.') '
		.'AND issuetype != Epic '
		.$query_customer;
#	print $jql."\n";
	my $search = eval {$jira_customer->POST('/search', undef, {
		'jql'	=> $jql,
		'startAt'    => 0,
		'maxResults' => 1000,
		'fields' => ['summary','key','updated','issuetype','status']
	})};
	exit if $@;
	push @issues, @{$search->{'issues'}};
}
if ($search_vendor_do)
{
	print "search vendor '$query_vendor'\n";
#				issuetype in standardIssueTypes() AND 
	my $jql = qq{
		(
			(
				Account = $customer_account AND
				project in ($vendor_project)
			)
			OR
			(
				project in ($vendor_sub_project)
			)
		)
	}.$query_vendor;
	my $search = eval {$jira_vendor->POST('/search', undef, {
		'jql'	=> $jql,
		'startAt'    => 0,
		'maxResults' => 1000,
		'fields' => ['summary','key','updated','issuetype','status']
	})};
	exit if $@;
	push @issues, @{$search->{'issues'}};
}

foreach my $issue (sort {$a->{'fields'}->{'updated'} cmp $b->{'fields'}->{'updated'}} @issues)
{
	# customer -> vendor
	my $name='customer';
	my $name_opposite='vendor';
	my $jira_src=$jira_customer;
	my $jira_dst=$jira_vendor;
	
	# vendor -> customer
	if ($issue->{'self'}=~/$vendor_self/)
	{
		$name='vendor';
		$name_opposite='customer';
		$jira_src=$jira_vendor;
		$jira_dst=$jira_customer;
	}
	
	$issue=$jira_src->GET('/issue/'.$issue->{'key'}.'?expand=transitions', undef);
	if ($name eq "vendor" && $issue->{'fields'}->{'parent'}->{'key'})
	{
		$issue=$jira_src->GET('/issue/'.$issue->{'fields'}->{'parent'}->{'key'}.'?expand=transitions', undef);
	}
#	print Dumper($issue);exit;
	
	$issue->{'source'}=uc(substr($name,0,1));
	
	$issue->{'reporter'} = $issue->{'fields'}->{'reporter'}->{'name'};
	$issue->{'assignee'} = $issue->{'fields'}->{'assignee'}->{'name'};
	
	$issue->{'fields'}->{'updated'}=~s|T| |;
	$issue->{'fields'}->{'updated'}=~s|\..*$||;
	
	if ($issue->{'source'} eq "C")
	{
		$datetime_customer_max = $issue->{'fields'}{'updated'}
			if $issue->{'fields'}{'updated'} gt $datetime_customer_max;
	}
	else
	{
		$datetime_vendor_max = $issue->{'fields'}{'updated'}
			if $issue->{'fields'}{'updated'} gt $datetime_vendor_max;
	}
	
	$issue->{'sub'}=0;
	$issue->{'sub'}=1 if (
		($issue->{'source'} eq "V" && $issue->{'key'}=~/^$vendor_sub_key/)
		|| ($issue->{'fields'}->{'issuetype'}->{'name'} eq 'Sub-task'));
	
	
	# read key_sync
	my $sth = $dbh->prepare("SELECT * FROM tasks WHERE id_$name=? LIMIT 1");
		$sth->execute($issue->{'key'});
	my $db0_line = $sth->fetchrow_hashref();
	$issue->{'key_sync'} = $db0_line->{'id_'.$name_opposite};
	$issue->{'updated_db'} = $db0_line->{'updated_'.$name};
	
	if ($issue->{'updated_db'} eq $issue->{'fields'}{'updated'}
		&& !$arg{'key'}
	)
	{
		next;
	}
	
	$synced++;
	
	my $source = from_json($db0_line->{'data_'.$name} || '{}');
	
	print $issue->{'source'}.": [".$issue->{'fields'}{'updated'}."] ";
	printf('%-9s', $issue->{'key'})." ";
	print "sub=".$issue->{'sub'}." ";
	printf('%-9s', $issue->{'fields'}->{'issuetype'}->{'name'})." ";
	printf('%-9s', $issue->{'fields'}->{'status'}->{'name'})." ";
	print " \"";
	printf('%-9s', $issue->{'fields'}->{'summary'});
	print "\" ";
	print "\n";
	
	print "   [".$issue->{'updated_db'}."] in db\n"
		if $issue->{'updated_db'};
	
	$issue->{'sub'}=0;
	$issue->{'sub'}=1 if (
		($issue->{'source'} eq "V" && $issue->{'key'}=~/^$vendor_sub_key/)
		|| ($issue->{'fields'}->{'issuetype'}->{'name'} eq 'Sub-task'));
	
	
	if ($issue->{'fields'}->{'status'}->{'name'}=~/Closed/
		&& $issue->{'fields'}->{'status'}->{'name'} eq $source->{'fields'}->{'status'}->{'name'}
		&& $issue->{'source'} eq "V"
	)
	{
		print "   . this is already closed issue, skip update\n";
		$synced--;
		next;
	}
	
	
	if (!$issue->{'key_sync'})
	{
		print "   ! missing dst issue\n";
		if ($issue->{'source'} eq "V" && $issue->{'key'}=~/^$vendor_sub_key/)
		{
			if ($issue->{'reporter'} eq $customer_user)
			{
				
				my $hasmaster;
				foreach my $master_issue(@{$issue->{'fields'}->{'issuelinks'}})
				{
					next unless $master_issue->{'type'}->{'name'} eq "Including";
					next unless $master_issue->{'inwardIssue'}->{'key'}=~/^$vendor_key\-/;
					$hasmaster=1;
					last;
				}
				
				if ($hasmaster)
				{
					print "   . this is sub-issue, linked to not-existing issue, skip sync\n";
					$synced--;
					next;
				}
				print "   . this is specific sub-issue, synchronized directly\n";
			}
			# issue assigned to customer
			elsif ($issue->{'assignee'} eq $customer_user)
			{
				print "   . this is sub-issue assigned to customer, synchronized directly\n";
			}
			else
			{
				print "   . this is only sub-issue, possibly not linked to issue, skip sync\n";
				$synced--;
				next;
			}
		}
		if ($issue->{'source'} eq "C" && $issue->{'sub'})
		{
#			print "   . this is only sub-issue from customer, ignoring\n";
#			$synced--;
#			next;
		}
		if ($issue->{'fields'}->{'status'}->{'name'}=~/(Closed|Cancelled|Resolved)/)
		{
			print "   . this is already closed issue, skip creation\n";
			$synced--;
			next;
		}
		
		print "   + creating dst issue\n";
		
		my $issue_dst;
		my %fields;
#		print Dumper($issue);exit;
#		print Dumper($issue);
		if ($issue->{'source'} eq "C" && $issue->{'sub'})
		{
			my $est=$issue->{'fields'}->{'timetracking'}->{'originalEstimate'};
			
			$fields{'duedate'}=$issue->{'fields'}->{'duedate'}
				if $issue->{'fields'}->{'duedate'};
			
			$fields{'reporter'} = {'name' => $customer_user};
			
#			# if assigned, use assignee as vendor
#			$fields{'assignee'}={'name' => $vendor_user} if $issue->{'assignee'};
			
			# if assigned to customer, then use it!
#			if ($issue->{'assignee'} eq $customer_user)
#			{
#				$fields{'assignee'}={'name' => $config->{'customer'}->{'assignee'}};
#			}
			
			my $sync_parent;
			if ($issue->{'fields'}->{'parent'}->{'key'})
			{
				print "   . $name parent issue ".$issue->{'fields'}->{'parent'}->{'key'}."\n";
				my $sth = $dbh->prepare("SELECT * FROM tasks WHERE id_$name=? LIMIT 1");
					$sth->execute($issue->{'fields'}->{'parent'}->{'key'});
				my $db0_line = $sth->fetchrow_hashref();
				$sync_parent=$db0_line->{'id_'.$name_opposite};
				print "   . $name_opposite parent issue is ".$sync_parent."\n";
			}
			
			my $data={
				'fields' => {
					'project'   => { 'key' => $vendor_sub_project },
#					'reporter'  => { 'name' => ($issue->{'reporter'} || $vendor_user)},
					'issuetype' => { 'name' =>
						($conversion{'customer2vendor'}{'issuetype'}{
								$issue->{'fields'}->{'issuetype'}->{'name'}
							} || 'Task')
					},
					'priority' => {'name'=>
						($conversion{'customer2vendor'}{'priority'}{
							$issue->{'fields'}->{'priority'}->{'name'}
						} || $issue->{'fields'}->{'priority'}->{'name'})
					},
					'summary' => $issue->{'fields'}->{'summary'},
					'description' => $issue->{'fields'}->{'description'} || '',
					'timetracking' => {
						'originalEstimate' => $est
#							"remainingEstimate": "5"
					},
					%fields
				},
			};
			
#			print Dumper($data);
#			last;
			
			$issue_dst=$jira_dst->POST('/issue', undef, $data);
#			print Dumper($issue_dst);
#			print "   . get issue ".$issue_dst->{'key'}."\n";
			$issue_dst=$jira_dst->GET('/issue/'.$issue_dst->{'key'}, undef);
			if ($sync_parent)
			{
				print "   . link issue ".$sync_parent.' to '.$issue_dst->{'key'}."\n";
				$jira_vendor->POST('/issueLink', undef, {
					"type" => {  "name" => "Including" },
					"inwardIssue" => { "key" => $sync_parent },
					"outwardIssue" => { "key" => $issue_dst->{'key'} },
				});
			}
#			next;
		}
		elsif ($issue->{'source'} eq "C")
		{
#			$fields{'customfield_10106'}=$issue->{'fields'}->{'customfield_10005'}
#				if $issue->{'fields'}->{'issuetype'}->{'name'} eq "Epic";
			
			$fields{'duedate'}=$issue->{'fields'}->{'duedate'}
				if $issue->{'fields'}->{'duedate'};
			
			# creating to vendor
			$issue_dst=$jira_vendor_servicedesk->POST('/request', undef, {
				'serviceDeskId' => ($config->{'vendor'}->{'servicedesk'} || 1),
				'requestTypeId' => ($config->{'vendor'}->{'servicedesk_requesttypeid'} || 6),
				'requestFieldValues' => {
					'summary' => $issue->{'fields'}->{'summary'},
					'description' => '*'.$issue->{'reporter'}.'*: '.$issue->{'fields'}->{'description'},
				}
			});
			$jira_dst->PUT('/issue/'.$issue_dst->{'issueKey'}, undef, {
				"fields" => {
					'customfield_'.$config->{'vendor'}->{'tempo_account_cf'} => "" . $customer_account,
					'issuetype' => { 'name' =>
						($conversion{'customer2vendor'}{'issuetype'}{
								$issue->{'fields'}->{'issuetype'}->{'name'}
							} || 'Task')
					},
					'priority' => {'name'=>
						($conversion{'customer2vendor'}{'priority'}{
							$issue->{'fields'}->{'priority'}->{'name'}
						} || $issue->{'fields'}->{'priority'}->{'name'})
					},
					%fields
				}
			});
			$issue_dst=$jira_dst->GET('/issue/'.$issue_dst->{'issueKey'}, undef);
		}
		else # source is vendor
		{
			$fields{'customfield_10005'}=$issue->{'fields'}->{'customfield_10106'}
				if $issue->{'fields'}->{'issuetype'}->{'name'} eq "Epic";
			$fields{'duedate'}=$issue->{'fields'}->{'duedate'}
				if $issue->{'fields'}->{'duedate'};
			
			# check if reporter exists
			my $response=$jira_dst->GET('/user/search?username='.$issue->{'reporter'}, undef, {});
			if ($response && $response->[0])
			{
				$fields{'reporter'} = {'name' => $response->[0]->{'name'}};
			}
			else
			{
				$fields{'reporter'} = {'name' => $vendor_user};
			}
			
			# creating to customer
#			$issue->{'reporter'}=$vendor_user if $issue->{'reporter'} eq $customer_user;
			
#			print Dumper($issue);
			# if assigned, use assignee as vendor
			$fields{'assignee'}={'name' => $vendor_user} if $issue->{'assignee'};
			# if assigned to customer, then use it!
			if ($issue->{'assignee'} eq $customer_user)
			{
				$fields{'assignee'}={'name' => $config->{'customer'}->{'assignee'}};
			}
			
			$issue_dst=$jira_dst->POST('/issue', undef, {
				'fields' => {
					'project'   => { 'key' => $customer_project },
#					'reporter'  => { 'name' => ($issue->{'reporter'} || $vendor_user)},
					'issuetype' => { 'name' =>
						($conversion{'vendor2customer'}{'issuetype'}{
								$issue->{'fields'}->{'issuetype'}->{'name'}
							} || 'Task')
					},
					'priority' => {'name'=>
						($conversion{'vendor2customer'}{'priority'}{
							$issue->{'fields'}->{'priority'}->{'name'}
						} || $issue->{'fields'}->{'priority'}->{'name'})
					},
					'summary' => $issue->{'fields'}->{'summary'},
					'description' => $issue->{'fields'}->{'description'} || '',
					%fields
				},
			});
			
#			exit;
		}
		
		$issue->{'key_sync'} = $issue_dst->{'key'};
		$issue_dst=$jira_dst->GET('/issue/'.$issue->{'key_sync'}, undef);
		
		$issue_dst->{'fields'}->{'updated'}=~s|T| |;
		$issue_dst->{'fields'}->{'updated'}=~s|\..*$||;
		
		# update tasks
		my $sth = $dbh->prepare("REPLACE INTO tasks (
			id_$name, id_$name_opposite,
			updated_$name, updated_$name_opposite,
			data_$name, data_$name_opposite
		) VALUES (?,?,?,?,?,?)");
		$sth->execute(
			$issue->{'key'},$issue_dst->{'key'},
			$issue->{'fields'}{'updated'},$issue_dst->{'fields'}{'updated'},
			to_json($issue,{ ascii => 1, pretty => 1 }),
			to_json($issue_dst,{ ascii => 1, pretty => 1 })
		);
		
		$source=$issue;
		
#		next;
#		# add links
#		$jira_vendor->POST('/issue/'.($sub_issue->{'key'}).'/remotelink', undef, {
#			'object' => {
#				'url' => $customer_url.'/browse/'.$sub_issue_customer->{'key'},
#				'title' => 'Remote issue '.$sub_issue_customer->{'key'}
#			},
#		});
#		$jira_customer->POST('/issue/'.($sub_issue_customer->{'key'}).'/remotelink', undef, {
#			'object' => {
#				'url' => $vendor_url.'/browse/'.$sub_issue->{'key'},
#				'title' => 'Remote issue '.$sub_issue->{'key'}
#			},
#		});
		
=head1
		# update tasks
		my $sth = $dbh->prepare(qq{
			UPDATE tasks SET
				id_$name_opposite = ?,
				updated_$name_opposite = ?,
				data_$name_opposite = ?
			WHERE
				id_$name = ?
			LIMIT 1
		});
		$sth->execute(
			$issue_dst->{'key'},
			$issue_dst->{'fields'}{'updated'},
			to_json($issue_dst,{ ascii => 1, pretty => 1 }),
			$issue->{'key'}
		);
=cut
	}
	
	if (!$source->{'key'}) # no source (previous) data available
	{
		print " - missing source data, saving\n";
		my $sth = $dbh->prepare("UPDATE tasks SET data_$name=? WHERE id_$name=? LIMIT 1");
			$sth->execute(to_json($issue,{ ascii => 1, pretty => 1 }),$issue->{'key'});
		next;
	}
	
#	print "   .remote ".$issue->{'key_sync'}."\n";
	my $issue_dst=eval{$jira_dst->GET('/issue/'.$issue->{'key_sync'}.'?expand=worklog,transitions', undef)};
	if (!$issue_dst->{'key'})
	{
#		$issues++;
		next;
#		next unless $issue_dst->{'key'};
	}
	die "can't find key" unless $issue_dst->{'key'};
	
	print "   . $name_opposite key $issue_dst->{'key'}\n";
	
	if ($issue_dst->{'fields'}->{'status'}->{'name'}=~/Closed/)
	{
		print "   . this is already closed issue, skip update\n";
		$synced--;
		next;
	}
	
	if ($issue->{'source'} eq "V" && $issue->{'sub'} && $issue_dst->{'fields'}->{'issuetype'}->{'name'} ne 'Sub-task')
	{
		my $master;
		foreach my $master_issue(@{$issue->{'fields'}->{'issuelinks'}})
		{
			next unless $master_issue->{'type'}->{'name'} eq "Including";
			next unless $master_issue->{'inwardIssue'}->{'key'}=~/^$vendor_key\-/;
			
			my $sth = $dbh->prepare("SELECT * FROM tasks WHERE id_$name=? LIMIT 1");
				$sth->execute($master_issue->{'inwardIssue'}->{'key'});
			my $db0_line = $sth->fetchrow_hashref();
			
			$master_issue->{'key_sync'} = $db0_line->{'id_'.$name_opposite};
			if ($master_issue->{'key_sync'})
			{
				die "   ! move manualy to as sub-task to master ".$master_issue->{'key_sync'}."\n";
			}
			
			last;
		}
	}
	
	# check original-estimated in master issue (not sub-issue)
	if (!$issue->{'sub'} && $issue->{'source'} eq "V")
	{
		my $est=$issue->{'fields'}->{'timetracking'}->{'originalEstimate'};
		my $est_dst=$issue_dst->{'fields'}->{'timetracking'}->{'originalEstimate'};
		print "   ? original-estimated=". $est ." $name_opposite=".$est_dst."\n";
		if ($est ne $est_dst && $issue_dst->{'fields'}->{'status'}->{'name'} ne "Closed")
		{
#			$fields{'timetracking'}{'originalEstimate'} = $est;
			$jira_dst->PUT('/issue/'.$issue->{'key_sync'}, undef, {
				"fields" => {
					'timetracking' => {
						'originalEstimate' => $est
					}
				}
			});
		}
	}
	elsif ($issue->{'sub'} && $issue->{'source'} eq "V")
	{
		my $est=$issue->{'fields'}->{'aggregatetimeoriginalestimate'};
		my $est_dst=$issue_dst->{'fields'}->{'timetracking'}->{'originalEstimateSeconds'};
		print "   ? original-estimated=". $est ." $name_opposite=".$est_dst."\n";
		if ($est ne $est_dst)
		{
			print "   = update est to ".$est."\n";
#			$fields{'timetracking'}{'originalEstimate'} = $est;
			$jira_dst->PUT('/issue/'.$issue->{'key_sync'}, undef, {
				"fields" => {
					'timetracking' => {
						'originalEstimate' => ($est/60)."m"
					}
				}
			});
		}
	}
	
	# check sub-issues
	# Vendor -> Customer
	if (!$issue->{'sub'} && $issue->{'source'} eq "V")
	{
		print "   ? check sub-issues\n"; # also linked issues
		
		foreach my $sub_issue(@{$issue->{'fields'}->{'issuelinks'}})
		{
#			print Dumper($sub_issue->{'type'});
			next unless $sub_issue->{'type'}{'id'} eq $vendor_sub_issue_type;
			$sub_issue=$sub_issue->{'outwardIssue'};
			
			my $sth = $dbh->prepare("SELECT * FROM tasks WHERE id_vendor=? LIMIT 1");
				$sth->execute($sub_issue->{'key'});
			my $db1_line = $sth->fetchrow_hashref();
				$sub_issue->{'key_sync'} = $db1_line->{'id_customer'};
			
			if (!$sub_issue->{'key_sync'})
			{
				$sub_issue=$jira_vendor->GET('/issue/'.$sub_issue->{'key'}, undef);
				
				my $est=$sub_issue->{'fields'}->{'timetracking'}->{'originalEstimate'};
				print "   + issue $sub_issue->{'key'} \"$sub_issue->{'fields'}->{'summary'}\" est=$est\n";
				
#				print Dumper($sub_issue->{'fields'});
				
#				exit;
				
				$sub_issue->{'fields'}->{'updated'}=~s|T| |;
				$sub_issue->{'fields'}->{'updated'}=~s|\..*$||;
				
				my %fields;
				$fields{'duedate'}=$sub_issue->{'fields'}->{'duedate'}
					if $sub_issue->{'fields'}->{'duedate'};
				
				my $sub_issue_customer=$jira_customer->POST('/issue', undef, {
					'fields' => {
						'parent' => {'key' => $issue->{'key_sync'}},
						'project'   => { 'key' => $customer_project },
						'reporter'  => { 'name' => $vendor_user},
						'assignee'  => { 'name' => $vendor_user},
						'issuetype' => { 'name' => 'Sub-task'},
						'summary' => $sub_issue->{'fields'}->{'summary'},
						'priority' => {'name' => $sub_issue->{'fields'}->{'priority'}->{'name'}},
						'description' => ($sub_issue->{'fields'}->{'description'} || ''),
						'timetracking' => {
							'originalEstimate' => $est
#							"remainingEstimate": "5"
						},
						%fields
					},
				});
				$sub_issue->{'key_sync'} = $sub_issue_customer->{'key'};
				$sub_issue_customer=$jira_customer->GET('/issue/'.$sub_issue->{'key_sync'}, undef);
				
				$sub_issue_customer->{'fields'}->{'updated'}=~s|T| |;
				$sub_issue_customer->{'fields'}->{'updated'}=~s|\..*$||;
				
				# update tasks
				my $sth = $dbh->prepare("REPLACE INTO tasks (
					id_vendor, id_customer,
					updated_vendor, updated_customer,
					data_vendor, data_customer
				) VALUES (?,?,?,?,?,?)");
				$sth->execute(
					$sub_issue->{'key'},$sub_issue->{'key_sync'},
					$sub_issue->{'fields'}{'updated'},
					$sub_issue_customer->{'fields'}{'updated'},
					to_json($sub_issue,{ ascii => 1, pretty => 1 }),
					to_json($sub_issue_customer,{ ascii => 1, pretty => 1 })
				);
				
				# add links
				$jira_vendor->POST('/issue/'.($sub_issue->{'key'}).'/remotelink', undef, {
					'object' => {
						'url' => $customer_url.'/browse/'.$sub_issue_customer->{'key'},
						'title' => $customer.' issue '.$sub_issue_customer->{'key'}
					},
				});
				$jira_customer->POST('/issue/'.($sub_issue_customer->{'key'}).'/remotelink', undef, {
					'object' => {
						'url' => $vendor_url.'/browse/'.$sub_issue->{'key'},
						'title' => $vendor.' issue '.$sub_issue->{'key'}
					},
				});
			}
			
		}
		
	}
	# Customer -> Vendor
	elsif (!$issue->{'sub'} && $issue->{'source'} eq "C")
	{
		print "   ? check sub-issues\n";
		
		foreach my $sub_issue(@{$issue->{'fields'}->{'subtasks'}})
		{
			$sub_issue=$jira_customer->GET('/issue/'.$sub_issue->{'key'}, undef);
			
			next if $sub_issue->{'fields'}->{'assignee'}->{'name'} ne $vendor_user;
#			print $vendor_user;
#			print Dumper($sub_issue);
			
			my $sth = $dbh->prepare("SELECT * FROM tasks WHERE id_customer=? LIMIT 1");
				$sth->execute($sub_issue->{'key'});
			my $db1_line = $sth->fetchrow_hashref();
				$sub_issue->{'key_sync'} = $db1_line->{'id_vendor'};
			
			
			if (!$sub_issue->{'key_sync'})
			{
				my $est=$sub_issue->{'fields'}->{'timetracking'}->{'originalEstimate'};
				print "   + issue $sub_issue->{'key'} \"$sub_issue->{'fields'}->{'summary'}\" est=$est\n";
				
				$sub_issue->{'fields'}->{'updated'}=~s|T| |;
				$sub_issue->{'fields'}->{'updated'}=~s|\..*$||;
				
				my %fields;
				$fields{'duedate'}=$sub_issue->{'fields'}->{'duedate'}
					if $sub_issue->{'fields'}->{'duedate'};				
				
				my $sub_issue_vendor=$jira_vendor->POST('/issue', undef, {
					'fields' => {
						'project'   => { 'key' => $vendor_sub_project },
						'reporter'  => { 'name' => $customer_user},
						'assignee'  => { 'name' => $customer_user},
						'issuetype' => { 'name' =>
							($conversion{'customer2vendor'}{'issuetype'}{
								$issue->{'fields'}->{'issuetype'}->{'name'}
							} || 'Task')
						},
						'summary' => $sub_issue->{'fields'}->{'summary'},
						'priority' => {'name' => $sub_issue->{'fields'}->{'priority'}->{'name'}},
						'description' => ($sub_issue->{'fields'}->{'description'} || ''),
						'timetracking' => {
							'originalEstimate' => $est || '1m'
#							"remainingEstimate": "5"
						},
						%fields
					},
				});
				
				$sub_issue->{'key_sync'} = $sub_issue_vendor->{'key'};
				$sub_issue_vendor=$jira_vendor->GET('/issue/'.$sub_issue->{'key_sync'}, undef);
				$sub_issue_vendor->{'fields'}->{'updated'}=~s|T| |;
				$sub_issue_vendor->{'fields'}->{'updated'}=~s|\..*$||;
				
				# update tasks
				my $sth = $dbh->prepare("REPLACE INTO tasks (
					id_customer, id_vendor,
					updated_customer, updated_vendor,
					data_customer, data_vendor
				) VALUES (?,?,?,?,?,?)");
				$sth->execute(
					$sub_issue->{'key'},$sub_issue->{'key_sync'},
					$sub_issue->{'fields'}{'updated'},
					$sub_issue_vendor->{'fields'}{'updated'},
					to_json($sub_issue,{ ascii => 1, pretty => 1 }),
					to_json($sub_issue_vendor,{ ascii => 1, pretty => 1 })
				);
				
				# add links
				$jira_customer->POST('/issue/'.($sub_issue->{'key'}).'/remotelink', undef, {
					'object' => {
						'url' => $vendor_url.'/browse/'.$sub_issue_vendor->{'key'},
						'title' => $vendor.' issue '.$sub_issue_vendor->{'key'}
					},
				});
				$jira_vendor->POST('/issue/'.($sub_issue_vendor->{'key'}).'/remotelink', undef, {
					'object' => {
						'url' => $customer_url.'/browse/'.$sub_issue->{'key'},
						'title' => $customer.' issue '.$sub_issue->{'key'}
					},
				});
				
				$jira_vendor->POST('/issueLink', undef, {
					"type" => {  "name" => "Including" },
					"inwardIssue" => { "key" => $issue_dst->{'key'} },
					"outwardIssue" => { "key" => $sub_issue_vendor->{'key'} },
				});
				
			}
			
		}
		
	}
	
	if ($issue->{'sub'} && $issue->{'source'} eq "V")
	{
		$issue->{'fields'}->{'description'}=~s|^[\n\r]?---[\n\r]+.*$||ms;
		
#		print "------------------------------------------------\n";
#		print $issue->{'fields'}->{'description'};
#		print "------------------------------------------------\n";
		
#		print Dumper($issue);
		if ($issue->{'fields'}->{'subtasks'})
		{
			$issue->{'fields'}->{'description'}.="\n"."---\n";
			foreach my $sub_issue(@{$issue->{'fields'}->{'subtasks'}})
			{
				$issue->{'fields'}->{'description'}.="- ".$sub_issue->{'fields'}->{'summary'}." *[".$sub_issue->{'fields'}->{'status'}->{'name'}."]*\n";
			}
		}
	}
	
#	print "------------------------------------------------\n";
#	print $issue->{'fields'}->{'description'};
#	print "------------------------------------------------\n";
	
	# read/set remote link
	$issue->{'remotelinks'}=$jira_src->GET('/issue/'.$issue->{'key'}.'/remotelink', undef);
	my $found;
	my $search_url=$vendor_url;
		$search_url=$customer_url if $issue->{'source'} eq "V";
	foreach my $link (@{$issue->{'remotelinks'}})
	{
		if ($link->{'object'}->{'url'}=~/^$search_url/)
		{
#			print "  found remote link\n";
			$found=1;
			last;
		}
	}
	if (!$found)
	{
		my $name_link=$vendor;
			$name_link=$customer if $issue->{'source'} eq "V";
		$jira_src->POST('/issue/'.($issue->{'key'}).'/remotelink', undef, {
			'object' => {
				'url' => $search_url.'/browse/'.$issue->{'key_sync'},
				'title' => $name_link.' issue '.$issue->{'key_sync'}
			},
		});
	}
	
	
	# worked
	if ($issue->{'source'} eq "V" && $issue_dst->{'fields'}->{'status'}->{'name'} ne "Closed")
	{
		$issue_dst->{'worklog'}=$jira_dst->GET('/issue/'.$issue_dst->{'key'}.'/worklog', undef);
		
		$issue->{'fields'}->{'aggregatetimespent'}||=0;
		if ($issue->{'fields'}->{'status'}->{'name'}=~/(Resolved|Closed)/)
		{
			$issue->{'fields'}->{'aggregatetimeestimate'}=0;
		}
		
		print "   ? worked=".int($issue->{'fields'}->{'aggregatetimespent'}/60)."m est.=".int($issue->{'fields'}->{'aggregatetimeestimate'}/60)."m\n";
		
		my $found=0;
		my $found_worklog;
		foreach my $worklog (@{$issue_dst->{'worklog'}->{'worklogs'}})
		{
			next unless $worklog->{'author'}->{'name'} eq $vendor_user;
			$found = $worklog->{'id'};
			$found_worklog = $worklog;
			last;
		}
		
		if (!$found && $issue->{'fields'}->{'aggregatetimespent'})
		{
			print "   + add worklog with ".int($issue->{'fields'}->{'aggregatetimespent'}/60)."m\n";
			$jira_dst->POST('/issue/'.($issue_dst->{'key'}).'/worklog'
				.'?adjustEstimate=new&newEstimate='.int($issue->{'fields'}->{'aggregatetimeestimate'}/60).'m'
				, undef, {
				'comment' => "JIRA Comsultia _aggregate summary_",
				'timeSpentSeconds' => $issue->{'fields'}->{'aggregatetimespent'},
			});
		}
		elsif ($issue->{'fields'}->{'aggregatetimespent'})
		{
			if ((int($found_worklog->{'timeSpentSeconds'}/60) ne int($issue->{'fields'}->{'aggregatetimespent'}/60))
				|| (int($issue_dst->{'fields'}->{'aggregatetimeestimate'}/60) ne int($issue->{'fields'}->{'aggregatetimeestimate'}/60)))
			{
				print "   = update worklog to ".int($issue->{'fields'}->{'aggregatetimespent'}/60)."m\n";
				$jira_dst->PUT('/issue/'.($issue_dst->{'key'}).'/worklog/'.$found
					.'?adjustEstimate=new&newEstimate='.int($issue->{'fields'}->{'aggregatetimeestimate'}/60).'m'
					, undef, {
					'comment' => "JIRA Comsultia _aggregate summary_",
					'timeSpentSeconds' => $issue->{'fields'}->{'aggregatetimespent'},
				});
			}
		}
		elsif ($issue->{'fields'}->{'aggregatetimeestimate'})
		{
			# set first estimate
		}
	}
	
	
	# attachments
	
		foreach my $attachment (@{$issue->{'fields'}->{'attachment'}})
		{
			my $sth = $dbh->prepare("SELECT * FROM attachments WHERE issue_$name_opposite=? AND filename=? LIMIT 1");
				$sth->execute($issue->{'key_sync'},$attachment->{'filename'});
			if (!$sth->rows)
			{
				print "   + file '".$attachment->{'filename'}."'\n";
				next if $attachment->{'filename'}=~/[á́éíóúčšžďťňľÔŽÉ]/;
				print "   = download and upload file\n";
				my $response = $jira_src->{'rest'}->getUseragent()->get(
					$attachment->{'content'},
					%{$jira_src->{'rest'}->{'_headers'}},
					'X-Atlassian-Token' => 'nocheck',
				);
				
				open(TMP,'>temp/'.$attachment->{'filename'});
				binmode(TMP);
				print TMP $response->decoded_content;
				close (TMP);
				
				$jira_dst->attach_files($issue->{'key_sync'}, 'temp/'.$attachment->{'filename'});
				
				unlink 'temp/'.$attachment->{'filename'};
				
				my $sth = $dbh->prepare("REPLACE INTO attachments (issue_$name,issue_$name_opposite,filename) VALUES (?,?,?)");
					$sth->execute($issue->{'key'},$issue->{'key_sync'},$attachment->{'filename'});
			}
		}
	
	$issue->{'labels'}=join ",",@{$issue->{'fields'}->{'labels'}};
	
	if (!$issue->{'sub'} || $issue->{'source'} eq "C" || $issue->{'labels'}=~/sync/)
	{
		if ($issue_dst->{'fields'}->{'status'}->{'name'} ne "Closed")
		{
#			print "check comments\n";
			# comments
			# TODO: check changes in comments
			foreach my $comment (@{$jira_src->GET('/issue/'.$issue->{'key'}.'/comment', undef)->{'comments'}})
			{
#				print "check comment id_$name=".$comment->{'id'}."\n";
				next if $comment->{'body'}=~/\/feedback\?token=/;
				my $body=$comment->{'body'};
					$body=~s|\n|\\n|gms;
					$body=~s|\t|\\t|gms;
					$body=~s|\r|\\r|gms;
					$body=substr($body,0,100);
				
				my $sth = $dbh->prepare("SELECT * FROM comments WHERE id_$name=? LIMIT 1");
					$sth->execute($comment->{'id'});
				
				$comment->{'source'} = '?';
				$comment->{'source'} = 'V' if $comment->{'author'}->{'emailAddress'}=~/$vendor_email_match/;
				$comment->{'source'} = 'C' if $comment->{'author'}->{'emailAddress'}=~/$customer_email_match/;
				
				if (!$sth->rows)
				{
					my $body=$comment->{'body'};
						$body='*'. $comment->{'author'}->{'name'} .'*: '.$body
							if ($issue->{'source'} eq "C" && $comment->{'source'} eq "C");
							
					$body=comment_text_replace($body,$issue->{'source'});
					
					my $body_=$body;
						$body_=~s|\n|\\n|gms;
						$body_=~s|\t|\\t|gms;
						$body_=~s|\r|\\r|gms;
						$body_=substr($body_,0,500);
					
					print '   + comment @'.$comment->{'author'}->{'name'}.' '.$issue->{'source'}.'/'.$comment->{'source'}.' "'.$body_."\"\n";
					
					die "unknown source of comment ".$comment->{'author'}->{'emailAddress'} if $comment->{'source'} eq "?";
					
					my $out = $jira_dst->POST('/issue/'.($issue->{'key_sync'}).'/comment', undef, {
						'body' => $body
					});
					my $sth = $dbh->prepare("REPLACE INTO comments (id_$name,id_$name_opposite,updated_$name) VALUES (?,?,?)");
						$sth->execute($comment->{'id'},$out->{'id'},$comment->{'updated'});
				}
			}
		}
	}
	
	
	my %fields;
	
	# summary
	if ($source->{'fields'}->{'summary'} ne $issue->{'fields'}->{'summary'}
		&& $issue->{'fields'}->{'summary'} ne $issue_dst->{'fields'}->{'summary'}
	)
	{
		$fields{'summary'} = $issue->{'fields'}->{'summary'};
		print "   'summary' to '".$fields{'summary'}."'\n";
	}
	
	
	
	# description
	$issue->{'fields'}->{'description'}=comment_text_replace($issue->{'fields'}->{'description'},$issue->{'source'});
	
	if ($issue->{'source'} eq "V")
	{
		$issue->{'fields'}->{'description'}=~s|^\*.*?\*: ||;
	}
	elsif ($issue->{'source'} eq "C")
	{
		$issue->{'fields'}->{'description'}=~s|^[\n\r]?---[\n\r]+.*$||ms;
		if ($issue->{'reporter'} ne $vendor_user)
		{
			$issue->{'fields'}->{'description'}=
				'*'.$issue->{'reporter'}.'*: '.$issue->{'fields'}->{'description'};
		}
	}
	
	if ($issue->{'fields'}->{'description'} ne $issue_dst->{'fields'}->{'description'})
	{
		$fields{'description'} = $issue->{'fields'}->{'description'};
		print "   'description' to '".$fields{'description'}."'\n";
	}
	
	# priority
	if ($source->{'fields'}->{'priority'}->{'name'} ne $issue->{'fields'}->{'priority'}->{'name'}
		&& $issue->{'fields'}->{'priority'}->{'name'} ne $issue_dst->{'fields'}->{'priority'}->{'name'}
	)
	{
		$fields{'priority'}->{'name'} = $issue->{'fields'}->{'priority'}->{'name'};
		print "   'priority' to '".$fields{'priority'}->{'name'}."'\n";
	}
	# duedate
	if (
		$source->{'fields'}->{'duedate'} ne $issue->{'fields'}->{'duedate'} &&
		$issue->{'fields'}->{'duedate'} ne $issue_dst->{'fields'}->{'duedate'}
	)
	{
		$fields{'duedate'} = $issue->{'fields'}->{'duedate'};
		print "   'duedate' to '".$fields{'duedate'}."'\n";
	}
	
	# issuetype
	my $fromto=$name.'2'.$name_opposite;
	if (($source->{'fields'}->{'issuetype'}->{'name'} ne $issue->{'fields'}->{'issuetype'}->{'name'})
		&& ($conversion{$fromto}->{'issuetype'}->{$issue->{'fields'}->{'issuetype'}->{'name'}} ne $issue_dst->{'fields'}->{'issuetype'}->{'name'})
		&& !$issue->{'sub'}
	)
	{
		print "   'issuetype' changed '".$source->{'fields'}->{'issuetype'}->{'name'}."'->'".$issue->{'fields'}->{'issuetype'}->{'name'}."'\n";
		$fields{'issuetype'}->{'name'} = $conversion{$fromto}->{'issuetype'}->{$issue->{'fields'}->{'issuetype'}->{'name'}};
		print "   'issuetype' to '".$fields{'issuetype'}->{'name'}."'\n";
	}
	
	if (keys %fields)
	{
		$jira_dst->PUT('/issue/'.$issue->{'key_sync'}, undef, {
			"fields" => {
				%fields
			}
		});
	}
	
	%fields=();
	
#=head1

	# status
	if ($source->{'fields'}->{'status'}->{'name'} ne $issue->{'fields'}->{'status'}->{'name'})
	{
		my $prefix;
			$prefix='sub-' if $issue->{'sub'};
			if ($issue->{'source'} eq "V" && $issue->{'sub'} && $issue_dst->{'fields'}->{'issuetype'}->{'name'} ne 'Sub-task')
			{
				# this is not a real sub-task with sub-task workflow
#				undef $prefix;
			}
			
		my $fromto=$name.'2'.$name_opposite;
		my $path=$source->{'fields'}->{'status'}->{'name'}.'->'.$issue->{'fields'}->{'status'}->{'name'};
		print "   'status' changed '".$source->{'fields'}->{'status'}->{'name'}."'->'".$issue->{'fields'}->{'status'}->{'name'}."'\n";
		my $opposite_status=$issue_dst->{'fields'}->{'status'}->{'name'};
		print "    : ".$name_opposite." issue in status '".$opposite_status."'\n";
		
		my $conversion_=$conversion{$fromto}->{$prefix.'statuspath'}->{$path}->{$opposite_status}
			|| $conversion{$fromto}->{$prefix.'statuspath'}->{$path}->{'*'};
#		$conversion_->{'path'}=[] unless $conversion_->{'path'};
#		push @{$conversion_->{'path'}},$conversion_->{'status'} if $conversion_->{'status'};
#		delete $conversion_->{'status'};
		
#		print Dumper($conversion_);
		
		if ($conversion_->{'ok'})
		{
			print "    . already in 'ok' state\n";
		}
		elsif ($conversion_->{'path'} && $conversion_->{'path'}[0])
		{
			
			print "    : known path='".join(",",@{$conversion_->{'path'}})."'\n";
			
			my $issue_dst=$jira_dst->GET('/issue/'.$issue->{'key_sync'}.'?expand=worklog,transitions', undef);
			foreach my $status (@{$conversion_->{'path'}})
			{
				$conversion_->{'status'}=$status;
				my $resolution=0;
					$resolution=$conversion{$fromto}->{'resolution-status'}->{$status}
						unless $issue->{'sub'};
				print "    = status '".$status."' resolution=$resolution\n";
				
#				exit;
				
				my $transition;
				foreach my $trans (@{$issue_dst->{'transitions'}})
				{
					if ($trans->{'to'}->{'name'} eq $conversion_->{'status'})
					{
						$transition=$trans;
						last;
					}
				}
				
				if (!$transition)
				{
					print "    ! can't find available transition\n";
					if (!@{$issue_dst->{'transitions'}})
					{
						next;
					}
					else
					{
						print Dumper($issue_dst->{'transitions'});
						die "can't find available transition";
					}
				}
				
				print "    : found transition '$transition->{'name'}'\n";
				
				my %fields;
				if ($resolution)
				{
					$fields{'fields'}{'resolution'}{'name'} = 
						$conversion{$fromto}->{'resolution'}->{$issue->{'fields'}->{'resolution'}->{'name'}}
						|| $issue->{'fields'}->{'resolution'}->{'name'};
						
					# asking for feedback
					
					
#					my $out = $jira_dst->POST('/issue/'.($issue->{'key_sync'}).'/comment', undef, {
#						'body' => $body
#					});
					
				}
				
				$jira_dst->POST('/issue/'.$issue->{'key_sync'}.'/transitions', undef, {
					'transition' => $transition->{'id'},
					%fields
				});
				
				$issue_dst=$jira_dst->GET('/issue/'.$issue->{'key_sync'}.'?expand=worklog,transitions', undef);
			}
			
		}
		elsif ($issue->{'source'} eq "C" && ($issue->{'fields'}->{'assignee'}->{'name'} ne $vendor))
		{
			print "    ! this is not assigned to mee, ignoring uknown path '$path'\n";
		}
		else
		{
			print "    ! unknown path '$path'\n";
			
			print Dumper($issue_dst->{'transitions'});
			
			die "unknown path '$path'";
		}
#		$fields{'issuetype'}->{'name'} = $issue->{'fields'}->{'issuetype'}->{'name'};
#		print "   'issuetype' to '".$fields{'issuetype'}->{'name'}."'\n";
	}
	
	
	# resolution
#	if ($source->{'fields'}->{'resolution'}->{'name'} ne $issue->{'fields'}->{'resolution'}->{'name'}
#		&& $issue->{'fields'}->{'resolution'}->{'name'} ne $issue_dst->{'fields'}->{'resolution'}->{'name'}
#	)
#	{
#		$fields{'resolution'}->{'name'} = $issue->{'fields'}->{'resolution'}->{'name'};
#		print "   'resolution' to '".$fields{'resolution'}->{'name'}."'\n";
#		exit;
#	}
	
	
	# update all changes
#	print "update $issue->{'key'} to '$issue->{'fields'}->{'updated'}'\n";
	my $sth = $dbh->prepare("UPDATE tasks SET data_$name=?, updated_$name=? WHERE id_$name=? LIMIT 1");
		$sth->execute(to_json($issue,{ ascii => 1, pretty => 1 }),$issue->{'fields'}->{'updated'},$issue->{'key'});
	
#	print Dumper($sth->rows());
#	print "datetime_max=$datetime_max\n";
	
	if (!$arg{'key'})
	{
		open(HND,'>jira_sync.datetime');
		print HND $datetime_customer_max."\n";
		print HND $datetime_vendor_max."\n";
		close(HND);
	}
	
#	exit;
	
#	print Dumper($issue);
#	last;
#	print "a\n";
#	$issue=$jira_customer->GET('/issue/'.$issue->{'key'}, undef);
}


sub replace_issue
{
	my $issue=shift;
	my $source=shift;
	my $name='customer';
		$name='vendor' if $source eq "V";
	my $name_opposite='vendor';
		$name_opposite='customer' if $source eq "V";
	my $sth = $dbh->prepare("SELECT * FROM tasks WHERE id_$name=? LIMIT 1");
		$sth->execute($issue);
	my $db0_line = $sth->fetchrow_hashref();
	return $db0_line->{'id_'.$name_opposite} || $issue;
}


sub comment_text_replace
{
	my $text=shift;
	my $source=shift;
	
	# mentioned issues
	$text=" ".$text." ";
	if ($source eq "V")
	{
		$text=~s/((?!browse\/).)($vendor_key\-\d+)/$1.replace_issue($2,$source)/ge;
		$text=~s/((?!browse\/).)($vendor_sub_key\-\d+)/$1.replace_issue($2,$source)/ge;
	}
	else
	{
		$text=~s/((?!browse\/).)($customer_key\-\d+)/$1.replace_issue($2,$source)/ge;
	}
	
	$text=~s|^ ||;$text=~s| $||;
	return $text;
}


print "\n";
if (!$synced)
{
	use DateTime;
	my $dt = DateTime->now('time_zone'=>'local');
	if (
		$dt->day_of_week() < 6
		&& $dt->day_of_week() > 0
		&& $dt->hour() >= 7
		&& $dt->hour() < 19
	)
	{
		print "sleep 30\n";
		sleep 30;
	}
	else
	{
		print "sleep 300\n";
		sleep 300;
	}
}

1;
