#!/usr/bin/perl

=head1 DESCRIPTION

	Consolidate the data obtained from JGI into one tabular file

=head1 USAGE

	perl consolidateJGIdata.pl -DIR path_to_the_JGI_files -OUT output_file.tsv

=head2 Options

	-DIR	-d	<STRING>	path to the files downloaded from JGI;	default=present working directory
	-OUT	-o	<STRING>	consolidated tab delimited file;		default=processID.tsv
	-genes	-g	<STRING>	produces a fasta file of all the genes in the given file;	default=not produced
	-script		<STRING>	location of the extractSubSeq.pl script;	default=/geomicro/data1/COMMON/scripts/extractSubSeq.pl
	
	-version -v	<BOOLEAN>	version of the current script
	-help	-h	<BOOLEAN>	This message. press "q" to exit this screen.

=head1 Author

	Sunit Jain, (Fri Jun  7 17:53:04 EDT 2013)
	sunitj [AT] umich [DOT] edu

=cut

use strict;
use Getopt::Long;
use File::Spec;
use POSIX ":sys_wait_h"; # qw(:signal_h :errno_h :sys_wait_h);

my $version="0.0.1b";
my $DIR="./";
my $out=$$.".tsv";
my $scripts="/geomicro/data1/COMMON/scripts/";
my $fasta;
GetOptions(
	'd|DIR:s'=>\$DIR,
	'o|OUT:s'=>\$out,
	'g|genes:s'=>\$fasta,
	'scripts:s'=>\$scripts,
	'v|version'=>sub{print $version."\n"; exit;},
	'h|help'=>sub{system('perldoc', $0); exit;},
);

# Get all File names in the given directory
unless ($DIR=~ m/\/$/){$DIR=$DIR."/";}
my @FILES=<$DIR*>;
my ($cog, $ec, $faa, $fna, $geneProd, $gff, $ko, $contigMap, $pfam, $phyloDist, $config);
foreach my $f(@FILES){
	 $cog=$f if ($f=~ /.*.a.cog.txt/);
	 $ec=$f if ($f=~ /.*.a.ec.txt/);
	 $faa=$f if ($f=~ /.*.a.faa/);
	 $fna=$f if ($f=~ /.*.a.fna/);
	 $geneProd=$f if ($f=~ /.*.a.gene_product.txt/);
	 $gff=$f if ($f=~ /.*.a.gff/);
	 $ko=$f if ($f=~ /.*.a.ko.txt/);
	 $contigMap=$f if ($f=~ /.*.a.map.txt/);
	 $pfam=$f if ($f=~ /.*.a.pfam.txt/);
	 $phyloDist=$f if ($f=~ /.*.a.phylodist.txt/);
	 $config=$f if ($f=~ /.*.config/);
}

# Run this bit on a seperate thread.
my %PIDs;
my $ess=File::Spec->catfile($scripts, "extractSubSeq.pl");
if ($fasta && -e $ess){
	my $pid=run("perl ".$scripts." -f ".$fna." -gff ".$gff." -o ".$fasta);
	$PIDs{$pid}++;
}

# Continue with the main script.

my $lgc=File::Spec->catfile($scripts, "length+GC.pl");
my $tmpLGC="tmp.lgc";
if(-e $lgc){
	system("perl $lgc -f $fna -gc > $tmpLGC");
}

# Aggregate data from different files.
## Locus Info ##

my %COGS;
open(COG, $cog) || die "[COG] $cog :\t$!";
while(my $line=<COG>){
	chomp $line;
	my(@cogData)=split(/\t/, $line);
	$COGS{$cogData[0]}=$cogData[1]."\t".$cogData[2]."\t"; #LocusID =  cog_id <TAB> %id
}
close COG;

my %PFAM;
open(PFAM, $pfam) || die "[PFAM] $pfam :\t$!";
while(my $line=<PFAM>){
	chomp $line;
	my(@pfamData)=split(/\t/, $line);
	$PFAM{$pfamData[0]}=$pfamData[1]."\t"; # LocusID = pfam_id
}
close PFAM;

my %TAXA;
open(TAXA, $phyloDist) || die "[PhyloDist] $phyloDist :\t$!";
while(my $line=<TAXA>){
	chomp $line;
	my(@taxaData)=split(/\t/, $line);
	my $locusID=shift @taxaData;
	$TAXA{$locusID}= join("\t", @taxaData);# LocusID = homolog_gene_id <TAB> homolog_taxon_id <TAB> %ID <TAB> Lineage
	$TAXA{$locusID}.="\t";
}
close TAXA;

my %KO;
open(KO, $ko) || die "[KO] $ko :\t$!";
while(my $line=<KO>){
	chomp $line;
	my(@koData)=split(/\t/, $line);
	$KO{$koData[0]}=$koData[2]."\t".$koData[3]."\t"; # LocusID =  ko_term <TAB> %id
}
close KO;

my %EC;
open(EC, $ec) || die "[EC] $ec :\t$!";
while(my $line=<EC>){
	chomp $line;
	my(@ecData)=split(/\t/, $line);
	$EC{$ecData[0]}=$ecData[2]."\t"; #LocusID =  EC
}
close EC;

my %PROD;
open(PROD, $geneProd) || die "[GENE_PROD] $geneProd :\t$!";
while(my $line=<PROD>){
	chomp $line;
	my(@prodData)=split(/\t/, $line);
	$PROD{$prodData[0]}=$prodData[1]."\t".$prodData[2]."\t"; # LocusID = product <TAB> Source
}
close PROD;

## Contig Info ##

my (%contig_name_map);
open(MAP, $contigMap) || die "[MAP] $contigMap :\t$!\n";
while(my $line=<MAP>){
	chomp $line;
	my ($original, $contigID)=split(/\t/, $line);
	$contig_name_map{$contigID}=$original;
}
close MAP;

my %LGC;
open(LGC, $tmpLGC) || die "[LGC] $tmpLGC :\t$!";
while(my $line=<LGC>){
	chomp $line;
	my @lgcData=split(/\t/, $line);
	$LGC{@lgcData[0]}=@lgcData[1]."\t".@lgcData[2]."\t"; # ContigID = %GC <TAB> Length
}
close LGC;
unlink $tmpLGC;

open(GFF, $gff) || die "[GFF] $gff :\t$!\n";
open(OUT, ">".$out) || die "[OUT] $out :\t$!\n";
print OUT "# Locus_Tag\tIMG_Gene_ID\tGene_Start\tGene_Stop\tGene_Length\tHomolog_Gene_ID\tHomolog_Taxon_ID\tLineage \%ID\tLineage\tProduct\tSource\tCOG_ID\tCog \%ID\tPFAM_ID\tKO_Term\tKO \%ID\tEC_Number\tIMG_Contig_Name\tOriginal_Contig_Name\tContig \%GC\tContig Length\n";
while(my $line=<GFF>){
	chomp $line;
	my($contigID, $locusID, $geneID, $start, $stop)=parseGFF3($line);
	my $printThis=$locusID."\t".$geneID."\t".$start."\t".$stop."\t";
	my($begin, $end)=sort{$a <=> $b}($start, $stop);
	$printThis.=($end - $begin)."\t";
	$printThis.=$TAXA{$locusID} ? $TAXA{$locusID} : "\t\t\t\t"; # homolog_gene_id <TAB> homolog_taxon_id <TAB> %ID <TAB> Lineage
	$printThis.=$PROD{$locusID} ? $PROD{$locusID} : "\t\t"; # product <TAB> Source
	$printThis.=$COGS{$locusID} ? $COGS{$locusID} : "\t\t"; # cog_id <TAB> %id
	$printThis.=$PFAM{$locusID} ? $PFAM{$locusID} : "\t"; # pfam_id
	$printThis.=$KO{$locusID} ? $KO{$locusID} : "\t\t"; # ko_term <TAB> %id
	$printThis.=$EC{$locusID} ? $EC{$locusID} : "\t"; # EC
	$printThis.=$contigID."\t".$contig_name_map{$contigID}."\t"; # IMG Contig Name <TAB> Original Contig Name
	$printThis.=$LGC{$contigID} ? $LGC{$contigID} : "\t\t"; # Contig %GC <TAB> Contig Length
	
	$printThis=~ s/\t$//;
	print OUT $printThis."\n";
}
close GFF;
close OUT;
undef %contig_name_map;
undef %COGS;
undef %PFAM;
undef %TAXA;
undef %KO;
undef %EC;
undef %PROD;

if ($fasta && $scripts){
	&REAP;
}

exit;

sub parseGFF3{
# http://gmod.org/wiki/GFF
	my $line=shift;
	my @cols=split(/\t/, $line);
	
	my(@attributes)=split(/\;/, $cols[-1]);
	
	my ($locusID, $geneID);
	my $contigID=$cols[0];
	my $start=$cols[3];
	my $stop=$cols[4];
	foreach my $att(@attributes){
		$locusID= $1 if ($att=~/locus_tag\=(.*)/);
		$geneID= $1 if ($att=~/^ID\=(.*)/);
	}
	if (! $locusID){
		foreach my $att(@attributes){
			if ($att=~/Parent\=(.*)/){
				$locusID=$1."_exon"
			}
			elsif($cols[2]=~/repeat/){
				$locusID=$1 if ($att=~/rpt_type\=(.*)/); # rpt_type=CRISPR;rpt_unit=13023..13055
				$locusID.="[ ".$1." ]" if ($att=~/rpt_unit\=(.*)/);
			}
			else{
				$locusID=$geneID."_".$cols[2];
			}
		}
	}
	return ($contigID, $locusID, $geneID, $start, $stop);
}

sub run{
	my $command=shift;
	my $pid = fork();

	if (!defined($pid)) {
    	die "unable to fork: $!";
	}
	elsif ($pid==0) { # child
		print "Executing:\t$command\n";
		exec($command) || die "unable to exec: [$?]\n$!\n";
		exit(0);
	}
	# parent continues here, pid of child is in $pid
	return($pid);
}

sub REAP{ ## Use this when you want to wait till the process ends before further processing.
	my $numPIDs= scalar(keys %PIDs);

	print "in REAPER: ".$numPIDs."\n";
	while (scalar(keys %PIDs) > 0){
		my $pid= waitpid(-1, &WNOHANG);
		if ($pid > 0){
			print "in REAPER:$pid\n";
			if (WIFEXITED($?) && $PIDs{$pid}){
				`echo "Process ID: $pid\tFinished with status $?"`;
#				$numPIDs-- ;
				print "Process: ".$pid."\tStatus: ".$?."\nWaiting for ".$numPIDs." more processes...\n";
				delete $PIDs{$pid};
			}
		}
		else{
			sleep 10;
		}
	}
	return;
}

