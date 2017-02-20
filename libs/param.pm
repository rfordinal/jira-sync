our %arg;
foreach my $key(@ARGV)
{
	$key=~s/^\-\-// && do
	{
		my @ref=split('=',$key,2);
		$ref[1]=1 unless exists $ref[1];
		if (ref($main::arg{$ref[0]}) eq "ARRAY")
		{
			push @{$main::arg{$ref[0]}},$ref[1];
		}
		elsif ($main::arg{$ref[0]})
		{
			my $oldval=$main::arg{$ref[0]};
			delete $main::arg{$ref[0]};
			$main::arg{$ref[0]}=[
				$oldval,
				$ref[1]
			];
		}
		else
		{
			$main::arg{$ref[0]}=$ref[1];
		}
		next;
	};
	$key=~s/^\-// && do
	{
		foreach (split('',$key)){$main::arg{$_}++;}
	};
}

1;
