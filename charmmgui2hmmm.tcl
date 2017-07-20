#This is a script designed to take full-length CHARMM-style membranes generated by CHARMM-GUI or other membrane generators and convert them to an HMMM representation.
#Usage: source charmmgui2hmmm.tcl
#hmmmize input.psf input.pdb $solvent $scalefactor
#Here $solvent is an optional parameter that specifies the HMMM solvent used. The default (0) is for conventional DCLE solvent. 1 generates SCSE solvent, and 2 generates SCSM solvent.
#$scalefactor controls the ratio between acyl carbons removed and the number of replacement particles. New solvents do not support values greater than 1.
package require psfgen
topology top_scs.top
topology patches.top
#These are availible from http://mackerell.umaryland.edu/CHARMM_ff_params.html
topology top_all36_lipid.rtf
topology top_all36_cgenff.rtf




#Algorithm goes like this:
#Find the C25 and C35 atoms in every molecule
#-Apply a patch to retype them and their substituents
#-Delete all atoms lower in the chain
#	-Store the locations of carbon atoms
#Use the stored carbon atom locations to generate solvent positions
proc hmmmize {psf pdb {solvent 0} {scalefactor 1}} {
	set mid [mol load psf $psf pdb $pdb]
	set sel [atomselect $mid "name \"C\[2-3\]5\""]
	puts [$sel num]
	resetpsf
	readpsf $psf
	coordpdb $pdb
	set coordlist [list ]
	foreach idx [$sel get index] {
		set atomsel [atomselect $mid "index $idx"]
		set sixfinder [atomselect $mid "index [lindex [$atomsel getbonds] 0]"]
		set sixindex [lindex [$sixfinder get index] [lsearch [$sixfinder get name] "C\[2-3\]6"]] ; # This logic depends on CHARMM-like atom naming.
		if {[$atomsel get name] == "C25"} {
			patch C25T "[$atomsel get segname]:[$atomsel get resid]"
		} elseif {[$atomsel get name] == "C35"} {
			patch C35T "[$atomsel get segname]:[$atomsel get resid]"
		} else {
			puts "Equality doesn't mean what I think it does."
		}
		lappend coordlist [crawl $mid $sixindex $idx]
		$sixfinder delete
		$atomsel delete
	}
	
	set carbonsremoved 0
	foreach acylchain $coordlist {
		puts $acylchain
		incr carbonsremoved [llength $acylchain]
	}
	puts "$carbonsremoved carbons removed"
	set carbonsremoved [expr {$scalefactor * $carbonsremoved}]
	#Need to regenerate solvents. Ratio of volume per CH2 is ~7:3 (DCLE:acyl)
	if {$solvent == 0} {
		set numdcle [expr { 3 * $carbonsremoved / 14}]
		puts "Adding $numdcle DCLE molecules to replace them."
		for {set i 0} {[expr {$i * 1000000}] < $numdcle} { incr i } {
			set segname HMM$i
			puts $segname
			segment $segname {
				for {set j 0} {[expr {($i * 1000000) + $j}] < $numdcle} {incr j} {
					residue $j DCLE
				}
			}
			for {set j 0} {[expr {$i * 1000000 + $j}] < $numdcle} {incr j} {
				set coords [lvarpop coordlist]
				set cordlen [llength $coords]
				if {$cordlen == 1} { ;#Place the DCLE according to the COM. Bond length equilibrium distance is 1.5 Angstroms.
					set rvec [vecscale 0.75 [randomunitvector]]
					set xyz [lvarpop coords]
					set xyz1 [vecadd $xyz $rvec]
					set xyz2 [vecsub $xyz $rvec]
				} else {
					set k [expr {int(rand()*($cordlen/2))}]
					set xyz1 [lindex $coords [expr {2*$k}]]
					set xyz2 [lindex $coords [expr {(2*$k)+1}]]
					set coords [lreplace $coords [expr {2*$k}] [expr {(2*$k)+1}]]
				}
				coord $segname $j C1 $xyz1
				coord $segname $j C2 $xyz2
				set rvec [randomunitvector]
				set v [vecnorm [vecsub $xyz1 $xyz2]] ;#V is the vector from C2 to C1
				set w [vecnorm [veccross $v $rvec]]
				set vrot [vecadd [vecscale -0.333807 $v] [vecscale 0.942641 [veccross $w $v]]]
				coord $segname $j CL11 [vecadd $xyz1 $vrot]
				if {[llength $coords] > 0} {
					lappend coordlist $coords
				}
			}
		}
	} elseif {$solvent == 1} { ;#SCSE
		set numscs [expr { $carbonsremoved / 2}]
		puts "Adding $numscs SCSE molecules to replace them."
		for {set i 0} {[expr {$i * 1000000}] < $numscs} { incr i } {
			set segname HMM$i
			puts $segname
			segment $segname {
				for {set j 0} {[expr {$i * 1000000 + $j}] < [expr { min($numscs, ($i + 1) * 1000000)}]} {incr j} {
					residue $j SCSE
				}
			}
			for {set j 0} {[expr {$i * 1000000 + $j}] < [expr { min($numscs, ($i + 1) * 1000000)}]} {incr j} {
				set coords [lvarpop coordlist]
				set cordlen [llength $coords]
				if {$cordlen == 1} {
					set rvec [vecscale 0.75 [randomunitvector]]
					set xyz [lvarpop coords]
					set xyz1 [vecadd $xyz $rvec]
					set xyz2 [vecsub $xyz $rvec]
				} else {
					set k [expr {int(rand()*($cordlen/2))}]
					set xyz1 [lindex $coords [expr {2*$k}]]
					set xyz2 [lindex $coords [expr {(2*$k)+1}]]
					set coords [lreplace $coords [expr {2*$k}] [expr {(2*$k)+1}]]
				}
				coord $segname $j C1 $xyz1
				coord $segname $j C2 $xyz2
				if {[llength $coords] > 0} {
					lappend coordlist $coords
				}
			}
		}
	} elseif {$solvent == 2} { ;#SCSM
		set numscs [expr { $carbonsremoved}]
		puts "Adding $numscs SCSM molecules to replace them."
		for {set i 0} {[expr {$i * 1000000}] < $numscs} { incr i } {
			set segname HMM$i
			puts $segname
			segment $segname {
				for {set j 0} {[expr {($i * 1000000) + $j}] < $numscs} {incr j} {
					residue $j SCSM
				}
			}
			for {set j 0} {[expr {$i * 1000000 + $j}] < $numscs} {incr j} {
				set coords [lvarpop coordlist]
				set cordlen [llength $coords]
				set k [expr {int(rand()*($cordlen))}]
				set xyz1 [lindex $coords $k]
				set coords [lreplace $coords $k $k]
				coord $segname $j C $xyz1
				if {[llength $coords] > 0} {
					lappend coordlist $coords
				}
			}
		}
	}
	$sel delete
	mol delete $mid
	regenerate angles dihedrals
	guesscoord
	
	
	writepsf hmmm-[file tail $psf]
	writepdb hmmm-[file tail $pdb]
}

#Traverses the acyl tails, deleting atoms as it goes.
proc crawl {molid index previd} {
	set centeratom [atomselect $molid "index $index"]
	set xyz [lindex [$centeratom get {x y z}] 0]
	set bondlist [lindex [$centeratom getbonds] 0]
	#Remove the atom from where we came already.
	set posn [lsearch -exact $bondlist $previd]
 	set bondlist [lreplace $bondlist $posn $posn]
 	foreach atomindex $bondlist {
 		set atom [atomselect $molid "index $atomindex"]
		#Are we going forward?
		if {[string match "C\[2-3\]\[0-9\]*" [$atom get name]]} {
			set xyzlist [crawl $molid $atomindex $index]
		} else {
			#Line that actually does the deleting.
			delatom [$atom get segname] [$atom get resid] [$atom get name]
		}
		$atom delete
 	}
 	delatom [$centeratom get segname] [$centeratom get resid] [$centeratom get name]
 	if {[info exists xyzlist]} {
 		lappend xyzlist $xyz
 	} else {
 		set xyzlist [list $xyz]
 	}
 	return $xyzlist
}

proc randomunitvector {} {
	set vec [list [expr {2.0 * rand() - 1}] [expr {2.0 * rand() - 1}] [expr {2.0 * rand() - 1}]]
	while {[veclength $vec] > 1.0} { ; #This forces vectors to be INSIDE the unit sphere.
		set vec [list [expr {2.0 * rand() - 1}] [expr {2.0 * rand() - 1}] [expr {2.0 * rand() - 1}]]
	}
	return [vecnorm $vec] 
}
