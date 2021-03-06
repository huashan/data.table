
bmerge = function(i, x, leftcols, rightcols, io, xo, roll, rollends, nomatch, verbose)
{
    # TO DO: rename leftcols to icols, rightcols to xcols
    # NB: io is currently just TRUE or FALSE for whether i is keyed
    # TO DO: io and xo could be moved inside Cbmerge
    # bmerge moved to be separate function now that list() doesn't copy in R
    # types of i join columns are promoted to match x's types (with warning or verbose)

    # Important that i is already passed in as a shallow copy, due to these coercions for factors.
    # i.e. bmerge(i<-shallow(i),...)  
    # The caller ([.data.table) then uses the coerced columns to build the output
    
    # careful to only plonk syntax (full column) on i from now on (otherwise i would change)
    # TO DO: enforce via .internal.shallow attribute and expose shallow() to users
    # This is why shallow() is very importantly internal only, currently.

    origi = shallow(i)      # Only needed for factor to factor joins, to recover the original levels
                            # Otherwise, types of i join columns are alyways promoted to match x's
                            # types (with warning or verbose)
    resetifactor = NULL  # Keep track of any factor to factor join cols (only time we keep orig)
    for (a in seq_along(leftcols)) {
        # This loop is simply to support joining factor columns
        # Note that if i is keyed, if this coerces, i's key gets dropped and the key may not be retained
        lc = leftcols[a]   # i   # TO DO: rename left and right to i and x
        rc = rightcols[a]  # x
        icnam = names(i)[lc]
        xcnam = names(x)[rc]
        if (is.character(x[[rc]])) {
            if (is.character(i[[lc]])) next
            if (!is.factor(i[[lc]]))
                stop("x.'",xcnam,"' is a character column being joined to i.'",icnam,"' which is type '",typeof(i[[lc]]),"'. Character columns must join to factor or character columns.")
            if (verbose) cat("Coercing factor column i.'",icnam,"' to character to match type of x.'",xcnam,"'.\n",sep="")
            set(i,j=lc,value=as.character(i[[lc]]))
            # no longer copies all of i, thanks to shallow() and :=/set
            next
        }
        if (is.factor(x[[rc]])) {
            if (is.character(i[[lc]])) {
                if (verbose) cat("Coercing character column i.'",icnam,"' to factor to match type of x.'",xcnam,"'. If possible please change x.'",xcnam,"' to character. Character columns are now preferred in joins.\n",sep="")
                set(i,j=lc,value=factor(i[[lc]]))
            } else {
                if (!is.factor(i[[lc]]))
                    stop("x.'",xcnam,"' is a factor column being joined to i.'",icnam,"' which is type '",typeof(i[[lc]]),"'. Factor columns must join to factor or character columns.")
                resetifactor = c(resetifactor,lc)
                # Retain original levels of i's factor columns in factor to factor joins (important when NAs,
                # see tests 687 and 688).
            }
            if (roll!=0.0 && a==length(leftcols)) stop("Attempting roll join on factor column x.",names(x)[rc],". Only integer, double or character colums may be roll joined.")   # because the chmatch on next line returns NA for missing chars in x (rather than some integer greater than existing). Note roll!=0.0 is ok in this 0 special floating point case e.g. as.double(FALSE)==0.0 is ok, and "nearest"!=0.0 is also true.
            newfactor = chmatch(levels(i[[lc]]), levels(x[[rc]]), nomatch=NA_integer_)[i[[lc]]]
            levels(newfactor) = levels(x[[rc]])
            class(newfactor) = "factor"
            set(i,j=lc,value=newfactor)
            # NAs can be produced by this level match, in which case the C code (it knows integer value NA)
            # can skip over the lookup. It's therefore important we pass NA rather than 0 to the C code.
        }
        if (is.integer(x[[rc]]) && is.double(i[[lc]])) {
            # TO DO: add warning if reallyreal about loss of precision
            # or could coerce in binary search on the fly, at cost
            if (verbose) cat("Coercing 'double' column i.'",icnam,"' to 'integer' to match type of x.'",xcnam,"'. Please avoid coercion for efficiency.\n",sep="")
            newval = i[[lc]]
            mode(newval) = "integer"  # retains column attributes (such as IDateTime class)
            set(i,j=lc,value=newval)
        }
        if (is.double(x[[rc]]) && is.integer(i[[lc]])) {
            if (verbose) cat("Coercing 'integer' column i.'",icnam,"' to 'double' to match type of x.'",xcnam,"'. Please avoid coercion for efficiency.\n",sep="")
            newval = i[[lc]]
            mode(newval) = "double"
            set(i,j=lc,value=newval)
        }
    }
        
    # Now that R doesn't copy named inputs to list(), we can return these as a list()
    # TO DO: could be allocated inside Cbmerge and returned as list from that
    f__ = integer(nrow(i))
    len__ = integer(nrow(i))
    allLen1 = logical(1)
    
    if (verbose) {last.started.at=proc.time()[3];cat("Starting bmerge ...");flush.console()}
    .Call(Cbmerge, i, x, as.integer(leftcols), as.integer(rightcols), io<-haskey(i), xo, roll, rollends, nomatch, f__, len__, allLen1)
    # NB: io<-haskey(i) necessary for test 579 where the := above change the factor to character and remove i's key
    if (verbose) {cat("done in",round(proc.time()[3]-last.started.at,3),"secs\n");flush.console}
    
    for (ii in resetifactor) set(i,j=ii,value=origi[[ii]])  # in the caller's shallow copy,  see comment at the top of this function for usage
    # We want to leave the coercions to i in place otherwise, since the caller depends on that to build the result
    
    return(list(starts=f__, lens=len__, allLen1=allLen1))
}


