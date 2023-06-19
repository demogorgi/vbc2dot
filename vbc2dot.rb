#!/usr/bin/ruby

#################################
# vbc2dot written by Uwe Gotzes #
#################################
#vbc2dot.rb is a Ruby-script that generates a .dot-file from scip's vbcfile output. It is supposed to be used along with scip as of version 5.0.1
#
#In scip, set visual/vbcfilename=vcbfilename and visual/dispsols=TRUE. After you have solved a problem, you can do
#>ruby vbc2dot.rb vbcfilename [options]
#This will generate you a visualization of the branch-and-bound-tree of the problem. The tool is still under development, but I think it generates reasonable results.
#You will need to have ruby and graphviz installed on your system. Alternatively you can use http://www.webgraphviz.com/.

#- Rubygems ----
require 'optparse'
require 'pp'

#- Option parser ----
# default options
rankdir   = "TB"
output    = ARGV[0]
legend    = false
delay     = 0
frequency = 1.0e+20

# parse arguments
ARGV.options do |opts|
    puts opts.banner = "\nUsage: #{File.basename(__FILE__)} vbcfilename [options]\n\n"
    opts.on("-r", "--rankdir=dirabbr", String, "\"TB\", \"LR\", \"BT\", \"RL\", corresponding to directed graphs drawn from top to bottom, from left to right, from bottom to top, and from right to left, respectively.") { |dirabbr| rankdir = dirabbr }
    opts.on("-o", "--output=filename", String, "Name of generated filenames. Postfixes are chosen automatically, default filename is vbcfilename.") { |filename| output = filename }
    opts.on("-l", "--legend", "Generate a legend in the output files.") { legend = true }
    opts.on("-d", "--delay=float", Float, "Wait d seconds until next ps-file is generated (movielike ps observation possible).") { |float| delay = float }
    opts.on("-f", "--frequency=int", Integer, "Generate output according to frequency.") { |int| frequency = int }
    opts.on("-t", "--probtype=minormax", String, "Use option if vbcfile does not contain any information on primal bounds.") { |minormax| ProbType = minormax }
    opts.parse!
end

# Minimization or maximization problem?
if File.foreach(ARGV[0]).grep(/[0-9] U [-0-9]/).any?
    ProbType = "min"
elsif File.foreach(ARGV[0]).grep(/[0-9] L [-0-9]/).any?
    ProbType = "max"
else
    raise "No primal bound exists in #{ARGV[0]}. Cannot decide if maximization or minimization problem. Use otpion -t."
end

class Numeric
    def nice
	if self.abs > 1.0e+20
	    return "--"
	end
	if self.to_s.length > 8
	    "%.3e" %(self)
	else
	    self
	end
    end

    def orderOfMagnitude
	if self == 0
	    1.0
	else
	    self.abs == self ? s = 1.0 : s = -1.0
	    s * 10.0 ** Math.log10(self.abs).floor
	end
    end

    def sigRound(d=8)
	i = self.to_f
	if d == 0
	    i.round
	else
	    (( ( i / i.orderOfMagnitude * 10.0 ** d ).round / 10.0 ** d ) * i.orderOfMagnitude).round(d)
	end
    end

    def sigRoundNice(d=8)
	sigRound(d).nice
    end

end


#- Useful constants ----
ColorHash = {
    "3" => "gold3",        #/**< color for newly created, unsolved nodes */
    "2" => "blue",         #/**< color for solved nodes */
    "4" => "red",          #/**< color for nodes that were cut off */
    "15" => "sandybrown",  #/**< color for nodes where a conflict constraint was found */
    "11" => "gray",        #/**< color for nodes that were marked to be repropagated */
    "12" => "steelblue",   #/**< color for repropagated nodes */
    "14" => "14",          #/**< color for solved nodes, where a solution has been found */
    "-1" => "black",       #/**< color should not be changed */
    "5" => "green",
    "99" => "plum"
}
# From scip source code
#/** node colors in VBC output:
# *   1: indian red
# *   2: green
# *   3: light gray
# *   4: red
# *   5: blue
# *   6: black
# *   7: light pink
# *   8: cyan
# *   9: dark green
# *  10: brown
# *  11: orange
# *  12: yellow
# *  13: pink
# *  14: purple
# *  15: light blue
# *  16: muddy green
# *  17: white
# *  18: light grey
# *  19: light grey
# *  20: light grey
# */
#enum SCIP_VBCColor
#{
#   SCIP_VBCCOLOR_UNSOLVED   =  3,       /**< color for newly created, unsolved nodes */
#   SCIP_VBCCOLOR_SOLVED     =  2,       /**< color for solved nodes */
#   SCIP_VBCCOLOR_CUTOFF     =  4,       /**< color for nodes that were cut off */
#   SCIP_VBCCOLOR_CONFLICT   = 15,       /**< color for nodes where a conflict constraint was found */
#   SCIP_VBCCOLOR_MARKREPROP = 11,       /**< color for nodes that were marked to be repropagated */
#   SCIP_VBCCOLOR_REPROP     = 12,       /**< color for repropagated nodes */
#   SCIP_VBCCOLOR_SOLUTION   = 14,       /**< color for solved nodes, where a solution has been found */
#   SCIP_VBCCOLOR_NONE       = -1        /**< color should not be changed */
#};
##################################

Identifier = /[ADINPLU]/
# vbc fileformat
# A, int char* Number of the node, information of the node.
# D, int int int int Number of the father, number of the new node, number of the new nodes colour and 1 or 0, depending if the tree has to be displayed with the new node or not.
# I, int char* Number of the node, information of the node.
# L, double The size of the lower bound.
# N, int int int Number of the father, number of the new node and number of the new nodes colour.
# P, int int Number of the node, number of the nodes colour.
# U, double The size of the upper bound.

#- Central Node class ----
class Node
    @@numberOfNodes = 0
    @@nodes = [nil]

    def initialize(name, fatherName, color, feasible=false)
	@name = name
	@fatherName = fatherName
	@moreInfo = nil
	@color = color
	@feasible = feasible
	if ProbType == "min"
	    @dualBound = 1.0e+99
	    @primalBound = 1.0e+99
	else
	    @dualBound = -1.0e+99
	    @primalBound = -1.0e+99
	end
	@branch = nil
	@depth = nil
	@@numberOfNodes += 1
	@@nodes << self
	@father = @@nodes[fatherName.to_i]
    end

    def self.numberOfNodes
	@@numberOfNodes
    end

    def self.nodes
	@@nodes
    end

    attr_accessor :color, :feasible, :dualBound, :primalBound, :branch, :depth, :name, :fatherName, :father, :moreInfo

    def graphvizLine(file)
	if @father != nil
	    file.write("        " + @fatherName + " -> " + @name + " [ label = \"#{@branch}\" ]" + ";\n")
	end
	if @dualBound.abs < 0.99 * 10**20 && Node.nodes[1].primalBound.abs < 0.99 * 10**20
	    if ( ProbType == "min" && @dualBound > Node.nodes[1].primalBound ) || ( ProbType == "max" && @dualBound < Node.nodes[1].primalBound ) # inferioriority
		@color = "plum"
	    elsif @primalBound == @dualBound # optimality
		@color = ColorHash["5"]
	    end
	end
	file.write("        " + @name + " [ label = \"#{@name}\\n#{@dualBound.sigRoundNice}\\n#{@primalBound.sigRoundNice}\", color = \"#{@color}\" ]" + ";\n")
    end

    def solutionFound(file)
	file.write("        " + @name + " [ style = \"filled\", fillcolor = \"palegreen\" ]" + ";\n")
    end
end

#- Useful methods ----
def systemcall(command)
    puts "Execute \"#{command}\""
    system(command)
end

def propagatePrimalBound(probtype, node)
    isBetterBound = true
    probtype == "min" ? rel = "<=" : rel = ">="
    while isBetterBound
	if node.father != nil
	    puts "Propagate primal bound from #{node.name}: primalBound = #{node.primalBound} #{rel} #{node.father.primalBound} = primalBound of father[#{node.name}] = #{node.father.name}"
	    if ( ProbType == "min" && node.father.primalBound >= node.primalBound ) || ( ProbType == "max" && node.father.primalBound <= node.primalBound )
		node.father.primalBound = node.primalBound
	    else
		isBetterBound = false
	    end
	    node = node.father
	else
	    break
	end
    end
end

def getNewNode(vbcLine, colorHash)
    # N, int int int
    # Number of the father, number of the newnode node and number of the newnode nodes colour.
    father, name, color = vbcLine.gsub(/^.*N /,"").scan(/\d+/)
    puts "newNode".ljust(24) + name.rjust(5) + ": color = " + colorHash[color].rjust(10) + "father = ".rjust(16) + father.rjust(10)
    [name, father, colorHash[color]]
end

def getNewNodeColor(vbcLine, colorHash)
    # P, int int 
    # Number of the node, number of the nodes colour.
    name, color = *vbcLine.gsub(/^.*P /,"").scan(/\d+/)
    puts "newNodeColor for node".ljust(24) + name.rjust(5) + ": color = " + colorHash[color].rjust(10)
    [name, colorHash[color]]
end

def getNewNodeInfo(vbcLine)
    # I, int char*
    # Number of the node, information of the node.
    splitArg = /\\t|\\i|\\n/
    newNodeInfo = vbcLine.gsub(/^.*I /,"").chomp.split(splitArg)
    name = newNodeInfo[0].gsub(" ","")
    depth = newNodeInfo[4]
    branch = newNodeInfo[6].sub(/(.*) (\[.*\]) ([<=>]*) (.*)/){ "#{$1} in #{$2}\n #{$1} #{$3} #{$4.to_f.sigRoundNice}" }
    dualBound = newNodeInfo[8].to_f
    puts "newNodeInfo for node".ljust(24) + name.rjust(5) + ": depth = " + depth.rjust(10) + "dualBound = ".rjust(16) + dualBound.sigRoundNice.to_s.rjust(10) + "   branch = #{branch.sub("\n"," ;  ")}"
    [name, depth, branch, dualBound]
end

def getMoreNodeInfo(vbcLine)
    # A, int char*
    # Number of the node, information of the node.
    splitArg = /\\t|\\i|\\n/
    moreNodeInfo = vbcLine.gsub(/^.*A /,"").chomp.split(splitArg)
    name = moreNodeInfo[0].gsub(" ","")
    info = moreNodeInfo[1]
    objVal = (info.match(/[-0-9.]+/)[0]).to_f
    puts "moreNodeInfo for node".ljust(24) + name.rjust(5) + ":" + "objVal = ".rjust(35) + objVal.to_s.rjust(10) + "     info = #{info}"
    [name, info, objVal]
end

def getNewPrimalBound(vbcLine)
    # [UL], double
    # The size of the primal bound.
    primalBound = (vbcLine.gsub(/^.*[UL] /,"").match(/\S+/)[0]).to_f
    puts "newPrimalBound for node     0:" + "primalBound = ".rjust(35) + primalBound.to_s.rjust(10)
    primalBound
end

def legendSubgraph(legend)
    str =  "        a -> d [ label = \"branching\\ninformation\" ];\n"
    str << "        a -> b;\n"
    str << "        b -> e;\n"
    str << "        b -> c;\n"
    str << "        d -> f;\n"
    str << "        d -> g;\n"
    str << "        e -> l;\n"
    str << "        f -> h;\n"
    str << "        f -> i;\n"
    str << "        g -> j;\n"
    str << "        g -> k;\n"
    str << "        a [ label = \"node name\\ndual bound\\nprimal bound\", color = #{ColorHash["2"]} ];\n"
    str << "        b [ label = \"solved\nnode\", color = #{ColorHash["2"]} ];\n"
    str << "        c [ label = \"in-\nfeasible\\ncutoff\", color = #{ColorHash["4"]}];\n"
    str << "        d [ label = \"solved\nnode\", color = #{ColorHash["2"]} ];\n"
    str << "        e [ label = \"marked\nfor\nrepropa-\ngation\", color = #{ColorHash["11"]} ];\n"
    str << "        f [ label = \"solved\nnode\", color = #{ColorHash["2"]} ];\n"
    str << "        g [ label = \"solved\nnode\", color = #{ColorHash["2"]} ];\n"
    str << "        h [ label = \"inferior\nnode\", color = #{ColorHash["99"]} ];\n"
    str << "        i [ label = \"newly\ncreated\nnot yet\nsolved\", color = #{ColorHash["3"]} ];\n"
    str << "        j [ label = \"conflict\ncon-\nstraint\nfound\", color = #{ColorHash["15"]} ];\n"
    str << "        k [ label = \"solved\nnode\nsolution\nfound\", color = #{ColorHash["5"]}, style = \"filled\", fillcolor = \"palegreen\" ];\n"
    str << "        l [ label = \"repro-\npagated\nnode\", color = #{ColorHash["12"]} ];\n"
    legend ? str : nil
end

def dotIt(output, delay, counter)
    systemcall("dot -Tps #{output}.dot -o #{output}.ps")
    sleep delay
    systemcall("dot -Tpdf #{output}.dot -o #{output}_#{counter.to_s.rjust(5,"0")}.pdf")
end

cnt = 1
File.foreach(ARGV[0]).with_index{ |vbcLine, vbcLine_num|
    #- Gather data from vbc-file ----
    if vbcLine.match(/^#/)
	next
    else
	ident = vbcLine.match(Identifier)[0]
	case ident
	when "N"
	    newNode = getNewNode(vbcLine, ColorHash)
	    Node.new(*newNode)
	when "I"
	    newNodeInfo = getNewNodeInfo(vbcLine)
	    node = Node.nodes[newNodeInfo[0].to_i]
	    node.dualBound = newNodeInfo[3]
	    node.depth = newNodeInfo[1]
	    node.branch = newNodeInfo[2]
	when "P"
	    index, color = *getNewNodeColor(vbcLine, ColorHash)
	    node = Node.nodes[index.to_i]
	    if color != "14"
		node.color = color
	    end
	when /[UL]/
	    newPrimalBound = getNewPrimalBound(vbcLine)
	when "A"
	    name, info, objVal = *getMoreNodeInfo(vbcLine)
	    node = Node.nodes[name.to_i]
	    node.moreInfo = info
	    node.feasible = true
	    node.primalBound = objVal
	    propagatePrimalBound(ProbType, node)
	else
	    raise "Identifier #{ident} in line #{vbcLine_num+1} not recognized."
	end
    end

    #- Write dot-file ----
    File.open(output + ".dot", "w") {|dotFile|
	dotFile.write("digraph finite_state_machine {\n\trankdir=#{rankdir};\n\tsize=\"11,17\" node [shape = circle];\n")
	dotFile.write(legendSubgraph(legend))
	Node.nodes.each{|node|
	    if node != nil
		node.graphvizLine(dotFile)
		if node.feasible
		    node.solutionFound(dotFile)
		end
	    end
	}
	dotFile.write("}")
    }

    #- Generate graphs with graphviz ----
    if cnt % frequency == 0
	dotIt(output, delay, cnt)
    end
    cnt += 1
}

dotIt(output, 0, cnt)
if frequency < 1.0e+20
    systemcall("pdftk #{output}*.pdf cat output all_#{output}.pdf")
end
systemcall("rm #{output}*.pdf")
