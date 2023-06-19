# vbc2dot
[vbc2dot.rb](https://github.com/demogorgi/vbc2dot/blob/main/vbc2dot.rb) is a Ruby-script that generates a .dot-file from [SCIP's](https://scipopt.org/) vbc-file output. Then the program [dot](https://graphviz.org/doc/info/command.html) is applied to the dot-file to generate a visualization of scip's branch-and-bound tree. In scip (>= 5.0.1), set visual/vbcfilename=vbcfilename and visual/dispsols=TRUE. After you have solved a problem, you can run ruby vbc2dot.rb vbcfilename [options], what will generate a visualization of the branch-and-bound tree of the problem. You will need to have ruby and graphviz installed on your system. Alternatively you could use webgraphviz. [This](https://github.com/demogorgi/vbc2dot/blob/main/all_vbcfile.vbc.pdf) is a sample output of vbc2dot (full tree evolution). Another [sample output](https://github.com/demogorgi/vbc2dot/blob/main/air04.vbc.pdf) of vbc2dot (final tree only) based upon the problem air04.mps from miplib.

```>ruby vbc2dot.rb -h``` yields:
````
Usage: vbc2dot.rb vbcfilename [options]

    -r, --rankdir=dirabbr            "TB", "LR", "BT", "RL", corresponding to directed graphs drawn from top to bottom, from left to right, from bottom to top, and from right to left, respectively.
    -o, --output=filename            Name of generated filenames. Postfixes are chosen automatically, default filename is vbcfilename.
    -l, --legend                     Generate a legend in the output files.
    -d, --delay=float                Wait d seconds until next ps-file is generated (movielike ps observation possible).
    -f, --frequency=int              Generate output according to frequency.
    -t, --probtype=minormax          Use option if vbcfile does not contain any information on primal bounds.
````
