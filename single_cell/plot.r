require(ggplot2)
require(ggrepel)
require(gtools)
require(cowplot)
require(tidyr)

source('~/code/single_cell/colors.r')
source('~/code/single_cell/map_gene.r')
#source('~/code/single_cell/tpm.r')
source('~/code/single_cell/scores.r')


qtrim = function(x, qmin=0, qmax=1, vmin=-Inf, vmax=Inf, rescale=NULL){
    
    # Trim by value
    x[x < vmin] = vmin
    x[x > vmax] = vmax
    
    # Trim by quantile
    u = quantile(x, qmin, na.rm=T)
    v = quantile(x, qmax, na.rm=T)
    x[x < u] = u
    x[x > v] = v

    return(x)
}


rescale_vector = function(x, target=c(0,1), f=identity, abs=FALSE){
    # Rescale vector onto target interval
    a = target[[1]]
    b = target[[2]]
    if(min(x) == max(x)){
        rep(min(target), length(x))
    } else {
        if(abs == TRUE){
            x = (x - min(abs(x)))/(max(abs(x)) - min(abs(x)))*(b - a) + a
        } else {
            x = (x - min(x))/(max(x) - min(x))*(b - a) + a
        }
        f(x)
    }
}										


load_signature = function(file=NULL, file.regex=NULL, file.cols=NULL){
    if(!file.exists(file)){file = paste0('~/aviv/db/markers/', file, '.txt')}
    sig = read.table(file, stringsAsFactors=F, row.names=1)
    sig = structure(strsplit(sig[,1], ','), names=rownames(sig))
    if(!is.null(file.regex)){file.cols = grep(file.regex, names(sig), value=T)}
    if(!is.null(file.cols)){sig = sig[file.cols]}
    return(sig)
}


plot_tsne = function(seur=NULL, names=NULL, scores=NULL, coords=NULL, data=NULL, meta=NULL, regex=NULL, files=NULL, file.cols=NULL, file.regex=NULL, top=NULL, ident=TRUE, data.use='log2',
                     combine_genes='mean', cells.use=NULL, ymin=0, ymax=1, num_col='auto', pt.size=.75, font.size=11, do.label=T, label.size=5, do.title=TRUE, title.use=NULL,
	             do.legend=TRUE, legend.title='log2(TPM)', share_legend=FALSE, legend_width=.05, vmin=NA, vmax=NA, na.value='transparent', out=NULL, nrow=1.5, ncol=1.5, ...){
    
    
    # TSNE coordinates
    if(is.null(coords)){
        d = structure(seur@tsne.rot[,1:2], names=c('x', 'y'))
    } else {
        d = structure(as.data.frame(coords[,1:2]), names=c('x', 'y'))
    }
    
    # Cell identities
    if(!is.logical(ident)){
        d$Identity = ident
    } else if(ident & !is.null(seur)){
        d$Identity = seur@ident
    }

    # Subset cells
    if(is.null(cells.use)){cells.use = rownames(d)}
    d = data.frame(d[cells.use,])
    
    # Cell scores
    scores = score_cells(seur=seur, data=data, meta=meta, names=names, regex=regex, files=files, file.cols=file.cols, file.regex=file.regex, top=top, scores=scores,
                         data.use='log2', combine_genes=combine_genes, cells.use=cells.use)
    if(!is.null(scores)){d = cbind.data.frame(d, scores)}
    
    # Initialize plotlist
    cat('\nPlotting:', paste(colnames(subset(d, select=-c(x,y))), collapse=', '), '\n')
    ps = list()

    # Shuffle point order
    d = d[sample(1:nrow(d)),]
    
    # Get limits for shared legend
    if(share_legend == TRUE){
        j = names(which(sapply(subset(d, select=-c(x,y)), is.numeric)))
	cat('\nShared limits:', paste(j, collapse=', '), '\n')
        if(is.na(vmin)){vmin = na.omit(min(d[,j]))}
	if(is.na(vmax)){vmax = na.omit(max(d[,j]))}
	cat('> vmin =', vmin, '\n> vmax =', vmax, '\n')
    }
    
    for(col in setdiff(colnames(d), c('x', 'y'))){

        # plot NAs first
        d = d[c(which(is.na(d[,col])), which(!is.na(d[,col]))),]
	    	
	if(is.numeric(d[,col])){
		    
	    # Continuous plot
	    d[,col] = qtrim(d[,col], qmin=ymin, qmax=ymax)
	    p = ggplot(d) +
	        geom_point(aes_string(x='x',y='y',colour=col), size=pt.size, ...) +
		scale_colour_gradientn(colours=material.heat(50), guide=guide_colourbar(barwidth=.5, title=legend.title), na.value=na.value, limits=c(vmin, vmax)) + 
		theme_cowplot(font_size=font.size) +
		xlab('TSNE 1') + ylab('TSNE 2')
		
	} else {
	    
	    # Discrete plot

	    # Get colors
	    if(do.label == TRUE){tsne.colors = tsne.colors} else {tsne.colors = set.colors}
	    
	    p = ggplot(d) +
	        geom_point(aes_string(x='x',y='y',colour=col), size=pt.size, ...) +
		theme_cowplot(font_size=font.size) +
		xlab('TSNE 1') + ylab('TSNE 2') +
		scale_colour_manual(values=tsne.colors, na.value=na.value) + 
		theme(panel.border = element_blank(), panel.grid.major = element_blank(), panel.grid.minor = element_blank())
	    
	    if(do.label == T){
	        t = aggregate(d[,c('x', 'y')], list(d[,col]), median)
		colnames(t) = c('l', 'x', 'y')
		p = p + geom_text_repel(data=t, aes(x=x, y=y, label=l, lineheight=.8), point.padding=NA, size=label.size, family='Helvetica') + theme(legend.position='none')
	    }
	}
	
	if(do.title == TRUE){
	    if(is.null(title.use)){title = col} else {title = title.use}
	    p = p + ggtitle(title)
	}
	if(do.legend == FALSE){p = p + theme(legend.position='none')}
	if(legend.title == ''){p = p + theme(legend.title=element_blank())}

	ps[[col]] = p
    }
    
    if(num_col == 'auto'){
        num_col = ceiling(sqrt(length(ps)))
    }
    
    ps = make_compact(plotlist=ps, num_col=num_col)
    if(length(ps) > 1){
        if(share_legend == TRUE){
            p = share_legend(ps, num_col=num_col, width=legend_width)
        } else {
            p = plot_grid(plotlist=ps, ncol=num_col, align='h')
        }
    }
    
    if(is.null(out)){
        p
    } else {
        save_plot(file=out, p, nrow=nrow, ncol=ncol)
    }
}


make_compact = function(plotlist, num_col, labels=TRUE, ticks=TRUE){
    
    # Make a "plot_grid" plotlist compact by removing axes from interior plots

    # x-axis
    if(length(plotlist) > num_col){
        i = setdiff(1:length(plotlist), rev(1:length(plotlist))[1:min(num_col, length(plotlist))])
	if(labels == TRUE){plotlist[i] = lapply(plotlist[i], function(p) p + theme(axis.title.x=element_blank()))}
	if(ticks == TRUE){plotlist[i] = lapply(plotlist[i], function(p) p + theme(axis.text.x=element_blank()))}
    }
    
    # y-axis
    if(num_col > 1){
        i = setdiff(1:length(plotlist), which(1:length(plotlist) %% num_col == 1))
	if(labels == TRUE){plotlist[i] = lapply(plotlist[i], function(p) p + theme(axis.title.y=element_blank()))}
	if(ticks == TRUE){plotlist[i] = lapply(plotlist[i], function(p) p + theme(axis.text.y=element_blank()))}
    }
    
    return(plotlist)
}


share_legend = function(plotlist, num_col, rel_widths=NULL, width=.1){
    
    # Get first legend in plotlist
    i = min(which(sapply(plotlist, function(p) 'guide-box' %in% ggplotGrob(p)$layout$name)))
    cat(paste('\nUsing shared legend:', names(plotlist)[i], '\n'))
    legend = get_legend(plotlist[[i]])
    
    # Remove all legends
    plotlist = lapply(plotlist, function(p) p + theme(legend.position='none'))
    
    # Make combined plot
    if(is.null(rel_widths)){rel_widths = rep(1, length(plotlist))}
    p = plot_grid(plotlist=plotlist, ncol=num_col, align='h', rel_widths=rel_widths)
    p = plot_grid(p, legend, ncol=2, rel_widths=c(1-width, width))
    
    return(p)
}


plot_heatmap = function(seur=NULL, names=NULL, scores=NULL, data=NULL, meta=NULL, regex=NULL, file=NULL, file.regex=NULL, file.cols=NULL, top=NULL, type='mean', group_by=NULL,
                        cells.use=NULL, do.scale=FALSE, scale_method='max', border='black', Rowv=TRUE, Colv=TRUE, labRow=NULL, labCol=NULL, qmin=0, qmax=1, vmin=-Inf, vmax=Inf, out=NA, ...){
    
    require(NMF)
    
    # Cell scores
    if(is.null(group_by)){group_by = seur@ident}
    data = get_scores(seur=seur, data=data, meta=meta, scores=scores, names=names, regex=regex, file=file, top=top, file.regex=file.regex, file.cols=file.cols, type=type, cells.use=cells.use, group_by=group_by)
    
    # Scale data
    if(do.scale == TRUE){
        if(scale_method == 'max'){
	    data = as.data.frame(t(t(data)/apply(data, 2, max)))
	} else {
	    data = scale(data)
	}
    }
    
    # Adjust scale
    data = qtrim(data, qmin=qmin, qmax=qmax, vmin=vmin, vmax=vmax)
    
    # Re-order rows
    i = order(apply(data, 1, which.max))
    data = data[i,,drop=F]
    
    # Plot heatmap
    if(ncol(data) == 1){Colv=NA}
    aheatmap(data, scale='none', border_color=border, Rowv=Rowv, Colv=Colv, labRow=labRow, labCol=labCol, hclustfun='average', filename=out, gp=gpar(lineheight=.8), ...)
}


heatmap2 = function(x, col='nmf', lmat=NULL, lwid=NULL, lhei=NULL, margins=c(5,5), rowSize=1, colSize=1, show.tree=TRUE, ...){
    library(gplots)

    # Make gplots heatmap.2 look like aheatmap
    
    # Adjust layout
    if(is.null(lmat)){lmat=matrix(c(0,2,3,1,4,0), nrow=2)}
    if(is.null(lwid)){lwid=c(.05,.9,.05)}
    if(is.null(lhei)){lhei=c(.05,.95)}

    # Label sizes
    cexRow = rowSize*(0.2 + 1/log10(nrow(x)))
    cexCol = colSize*(0.2 + 1/log10(ncol(x)))
    
    # NMF colors
    if(col == 'nmf'){col = colorRampPalette(nmf.colors)(100)} else {col = colorRampPalette(brewer.pal(9, col))(100)}

    # Hide dendrogram
    if(show.tree == FALSE){dendrogram='none'} else {dendrogram='both'}
    
    # Plot data
    heatmap.2(x, trace='none', lmat=lmat, lhei=lhei, lwid=lwid, col=col, cexRow=cexRow, cexCol=cexCol, dendrogram=dendrogram, ...)
}


ggheatmap = function(data, Rowv='hclust', Colv='hclust', xlab='', ylab='', xsec=FALSE, ysec=FALSE, xstag=FALSE, xstag_space=.15, ystag=FALSE, ystag_space=.15, title='', legend.title='',
                     pal='nmf', do.legend=TRUE, font_size=7, 
                     out=NULL, nrow=1.25, ncol=1.25, qmin=0, qmax=1, vmin=-Inf, vmax=Inf, symm=FALSE, xstrip=NULL, ystrip=NULL, hclust_met='complete', border='#cccccc', replace_na=NA,
		     labRow=NULL, labCol=NULL, ret.order=FALSE, ret.legend=FALSE, pvals=NULL, max_pval=1, pval_border='black'){
    
    require(ggplot2)
    require(tidyr)
    require(cowplot)
    require(tibble)
        
    # Fix input data
    if(ncol(data) == 3){
        colnames(data) = c('row', 'col', 'value')
	new_names = levels(as.factor(data$col))
        data = data.frame(spread(as.data.frame(data), col, value), row.names=1)
	colnames(data) = new_names
    }
    
    # Scale values
    data[is.na(data)] = replace_na
    data = qtrim(data, qmin=qmin, qmax=qmax, vmin=vmin, vmax=vmax)
    
    # Convert to long format
    x = as.data.frame(data) %>% rownames_to_column('row') %>% gather(col, value, -row)
    x$value = as.numeric(x$value)
    
    # Merge data and p-values
    if(is.null(pvals)){
        x$pval = border
    } else {
        if(ncol(pvals) == 3){
	    colnames(pvals) = c('row', 'col', 'pval')
	    pvals$row = as.character(pvals$row)
	    pvals$col = as.character(pvals$col)
	} else {
	    pvals = as.data.frame(pvals) %>% rownames_to_column('row') %>% gather(col, pval, -row)
	    pvals$pval = as.numeric(pvals$pval)
	}
	if(length(intersect(x$row, pvals$row)) == 0){
	    colnames(pvals) = c('col', 'row', 'pval')
	}
	x = as.data.frame(merge(as.data.table(x), as.data.table(pvals), by=c('row', 'col'), all.x=TRUE))
	x$pval = ifelse(x$pval <= max_pval, pval_border, NA)
	x$pval[is.na(x$pval)] = border
    }
    
    # Order rows
    if(length(Rowv) > 1){rowv = Rowv; Rowv = 'Rowv'} else {rowv = rev(rownames(data))}
    if(length(Colv) > 1){colv = Colv; Colv = 'Colv'} else {colv = colnames(data)}
    if(nrow(data) <= 2){Rowv = 'none'}
    if(ncol(data) <= 2){Colv = 'none'}
    if(Rowv == 'hclust'){
        rowv = rev(rownames(data)[hclust(dist(data), method=hclust_met)$order])
    }
    if(Colv == 'hclust'){
        colv = colnames(data)[hclust(dist(t(data)), method=hclust_met)$order]
    }
    if(Rowv == 'none'){
        rowv = rev(rownames(data))
    }
    if(Colv == 'none'){
        colv = colnames(data)
    }
    if(Rowv == 'min'){
        rowv = rev(rownames(data)[order(apply(data, 1, which.min))])
    }
    if(Rowv == 'max'){
        rowv = rev(rownames(data)[order(apply(data, 1, function(a) order(-a)[1:2]))])
        #rowv = rev(rownames(data)[order(apply(data, 1, which.max))])
    }
    if(Colv == 'min'){
        i = match(rownames(data)[apply(data, 2, which.min)], rowv)
	colv = rev(colnames(data)[order(i)])        
    }
    if(Colv == 'max'){
	i = match(rownames(data)[apply(data, 2, which.max)], rowv)
	colv = rev(colnames(data)[order(i)])
    }
    Rowv = rowv
    Colv = colv

    # Set order of row and column labels
    x$row = factor(x$row, levels=Rowv)
    x$col = factor(x$col, levels=Colv)
    
    # Get odd/even indices
    r1 = seq(1, length(Rowv), by=2)
    r2 = seq(2, length(Rowv), by=2)
    c1 = seq(1, length(Colv), by=2)
    c2 = seq(2, length(Colv), by=2)
    
    # Get plot data
    if(length(pal)==1){if(pal == 'nmf'){pal = rev(colorRampPalette(nmf.colors)(100))[10:100]} else {pal = colorRampPalette(brewer.pal(9, pal))(100)}}
    
    # Plot significant boxes last
    x = x[rev(order(x$pval != 'black')),]
        
    # Plot with geom_tile
    p = ggplot(x) +
        geom_tile(aes(x=as.numeric(col), y=as.numeric(row), fill=value), color=x$pval) +
	labs(x=xlab, y=ylab, title=title, fill=legend.title) +
	theme_cowplot(font_size=font_size) +
	theme(axis.text.x=element_text(angle=90, hjust=1, vjust=.5), axis.line=element_blank())
    
    # Set scale
    if(is.infinite(vmin)){vmin = min(x$value)}
    if(is.infinite(vmax)){vmax = max(x$value)}
    limits = c(vmin, vmax)
    if(symm == TRUE){
        max_value = max(abs(x$value))
	values = seq(-max_value, max_value, length=3)
        p = p + scale_fill_gradientn(colours=pal, values=values, rescaler=function(x, ...) x, oob=identity, limits=limits)
    } else {
        p = p + scale_fill_gradientn(colours=pal, limits=limits)
    }
    
    # Secondary x-axis
    if(xsec == FALSE){
        p = p + scale_x_continuous(breaks=1:length(Colv), labels=Colv, expand=c(0,0))
    } else {
	p = p + scale_x_continuous(breaks=c1, labels=Colv[c1], sec.axis=dup_axis(breaks=c2, labels=Colv[c2]), expand=c(0,0)) + theme(axis.text.x.top= element_text(angle=90, hjust=0, vjust=.5))
    }
    
    # Secondary y-axis
    if(ysec == FALSE){
        p = p + scale_y_continuous(breaks=1:length(Rowv), labels=Rowv, expand=c(0,0))
    } else {
	p = p + scale_y_continuous(breaks=r1, labels=Rowv[r1], sec.axis=dup_axis(breaks=r2, labels=Rowv[r2]), expand=c(0,0))
    }
    
    # Add axes with ggrepel (use both sides to fit as many labels as possible)
    if(!is.null(labRow)){
        p = p + theme(axis.text.y=element_blank(), axis.ticks.y=element_blank())
	if(!is.logical(labRow)){
	    lab.use = intersect(Rowv, labRow)
	    lab.l = ifelse(Rowv %in% lab.use[seq(from=1, to=length(lab.use), by=2)], Rowv, '')
	    lab.r = ifelse(Rowv %in% lab.use[seq(from=2, to=length(lab.use), by=2)], Rowv, '')
	    legend = get_legend(p)
	    p = p + theme(legend.position='none', plot.margin=margin(l=-10, unit='pt'))
	    axis.l = add_ggrepel_axis(plot=p, lab=lab.l, type='left', font_size=font_size, do.combine=FALSE)
	    axis.r = add_ggrepel_axis(plot=p, lab=lab.r, type='right', font_size=font_size, do.combine=FALSE)
	    p = plot_grid(axis.l, p, axis.r, nrow=1, rel_widths=c(.15,1,.15), align='h', axis='tb')
	    p = plot_grid(p, legend, nrow=1, rel_widths=c(.925, .075))	    
	}
    }
    
    if(!is.null(labCol)){
        p = p + theme(axis.text.x=element_blank(), axis.ticks.x=element_blank())
	if(!is.logical(labCol)){
	    lab.use = intersect(Colv, labCol)
	    lab.u = ifelse(Colv %in% lab.use[seq(from=1, to=length(lab.use), by=2)], Colv, '')
	    lab.d = ifelse(Colv %in% lab.use[seq(from=2, to=length(lab.use), by=2)], Colv, '')
	    legend = get_legend(p)
	    p = p + theme(legend.position='none', plot.margin=margin(t=-10, b=-12.5, unit='pt'))
	    axis.u = add_ggrepel_axis(plot=p, lab=lab.u, type='up', font_size=font_size, do.combine=FALSE)
	    axis.d = add_ggrepel_axis(plot=p, lab=lab.d, type='down', font_size=font_size, do.combine=FALSE)
	    p = plot_grid(axis.u, p, axis.d, nrow=3, rel_heights=c(.15,1,.15), align='v', axis='lr')
	    p = plot_grid(p, legend, nrow=1, rel_widths=c(.925, .075))
	}
    }
    
    if(xstag == TRUE){
        nudge = rep(c(0, 1), length.out=length(Colv))
	p = add_ggrepel_axis(plot=p, lab=Colv, dir='x', type='down', font_size=font_size, force=0, axis.width=xstag_space, nudge=nudge, ret.legend=ret.legend)
    }
    
    if(ystag == TRUE){
        nudge = rep(c(0, 1), length.out=length(Rowv))
	p = add_ggrepel_axis(plot=p, lab=Rowv, dir='y', type='left', font_size=font_size, force=0, axis.width=ystag_space, nudge=nudge, ret.legend=ret.legend)
    }
        
    if(do.legend == FALSE){p = p + theme(legend.position='none')}
    
    # Save plot
    if(!is.null(out)){
        save_plot(p, file=out, nrow=nrow, ncol=ncol)
    }
    
    if(ret.order == FALSE){p} else {list(p=p, Rowv=Rowv, Colv=Colv)}
}


add_ggrepel_axis = function(plot, lab, dir='both', type='left', lab.pos=NULL, lab.lim=NULL, nudge=0, force=1, axis.width=.10, legend.width=.075, font_size=8, ret.legend=FALSE){
    
    library(ggrepel)
    
    # Fix input arguments
    if(is.null(lab.pos)){lab.pos = 1:length(lab)}
    if(is.null(lab.lim)){lab.lim = c(min(lab.pos)-1, max(lab.pos)+1)}
    
    # Set label directions
    if(type == 'left'){x=0; y=lab.pos; xlim=c(-1,0); ylim=lab.lim; angle=0; nudge_x=-1*nudge; nudge_y=0}
    if(type == 'up'){x=lab.pos; y=0; xlim=lab.lim; ylim=c(0,1); angle=90; nudge_x=0; nudge_y=nudge}
    if(type == 'right'){x=0; y=lab.pos; xlim=c(0,1); ylim=lab.lim; angle=0; nudge_x=nudge; nudge_y=0}
    if(type == 'down'){x=lab.pos; y=0; xlim=lab.lim; ylim=c(-1,0); angle=90; nudge_x=0; nudge_y=-1*nudge}
    
    # Get data for ggplot
    d = data.frame(x=x, y=y, lab=lab, dir=dir, nudge_y=nudge_y)
    
    # Make ggrepel axis
    axis = ggplot(d, aes(x=x, y=y, label=lab)) +
           geom_text_repel(min.segment.length=grid::unit(0,'pt'), color='grey30', size=(font_size-1)/.pt, angle=angle, segment.color='#cccccc', segment.size=.15,
	                   direction=dir, nudge_x=nudge_x, nudge_y=nudge_y, force=force) +
	   scale_x_continuous(limits=xlim, expand=c(0,0), breaks=NULL, labels=NULL, name=NULL) +
	   scale_y_continuous(limits=ylim, expand=c(0,0), breaks=NULL, labels=NULL, name=NULL) +
    	   theme(panel.background = element_blank(), plot.margin = margin(0, 0, 0, 0, 'pt'))
    
    # Get plot legend
    legend = get_legend(plot)
    plot = plot + theme(legend.position='none')
    
    # Combine plots
    if(type == 'left'){
        plot = plot + scale_y_continuous(limits=lab.lim, expand=c(0,0))    
        plot = plot + theme(plot.margin=margin(l=-12.5, unit='pt')) + theme(axis.text.y=element_blank(), axis.ticks.y=element_blank())
	p = plot_grid(axis, plot, nrow=1, align='h', axis='tb', rel_widths=c(axis.width, 1-axis.width))
	if(ret.legend == FALSE){p = plot_grid(legend, p, nrow=1, rel_widths=c(legend.width, 1-legend.width))}
    }
    if(type == 'up'){
        plot = plot + scale_x_continuous(limits=lab.lim, expand=c(0,0))
        plot = plot + theme(plot.margin=margin(t=-10, unit='pt')) + theme(axis.text.x=element_blank(), axis.ticks.x=element_blank())
	p = plot_grid(axis, plot, nrow=2, align='v', axis='lr', rel_heights=c(axis.width, 1-axis.width))
	if(ret.legend == FALSE){p = plot_grid(legend, p, nrow=1, rel_widths=c(legend.width, 1-legend.width))}
    }
    if(type == 'right'){
        plot = plot + scale_y_continuous(limits=lab.lim, expand=c(0,0))
        plot = plot + theme(plot.margin=margin(r=-10, unit='pt')) + theme(axis.text.y=element_blank(), axis.ticks.y=element_blank())
	p = plot_grid(plot, axis, nrow=1, align='h', axis='tb', rel_widths=c(1-axis.width, axis.width))
	if(ret.legend == FALSE){p = plot_grid(p, legend, nrow=1, rel_widths=c(1-legend.width, legend.width))}
    }
    if(type == 'down'){
        plot = plot + scale_x_continuous(limits=lab.lim, expand=c(0,0))
        plot = plot + theme(plot.margin=margin(b=-11.5, t=5, unit='pt')) + theme(axis.text.x=element_blank(), axis.ticks.x=element_blank())
	p = plot_grid(plot, axis, nrow=2, align='v', axis='lr', rel_heights=c(1-axis.width, axis.width))
	if(ret.legend == FALSE){p = plot_grid(p, legend, nrow=1, rel_widths=c(1-legend.width, legend.width))}
    }
    
    if(ret.legend == FALSE){p} else {list(p=p, legend=legend)}
}


plot_dots = function(seur=NULL, names=NULL, scores=NULL, data=NULL, meta=NULL, regex=NULL, files=NULL, file.regex=NULL, file.cols=NULL, top=NULL, groups=NULL, cells.use=NULL,
                     dot_size='alpha', dot_color='mu', font_size=8, reorder=FALSE,
	             rescale=FALSE, do.title=TRUE, do.legend=TRUE, xlab='Cell Type', ylab='Gene', out=NULL, nrow=1.5, ncol=1.5, coord_flip=FALSE, max_size=5){
    
    require(tibble)
    
    # Fix input arguments
    if(is.null(groups)){groups = seur@ident}
    if(is.null(cells.use)){cells.use = colnames(seur@data)}
    
    # Get dot sizes and colors (default = alpha and mu)
    x = score_cells(seur=seur, data=data, meta=meta, scores=scores, names=names, regex=regex, files=files, file.regex=file.regex, file.cols=file.cols, top=top, cells.use=cells.use,
        groups=groups, group_stat=dot_size)
    
    y = score_cells(seur=seur, data=data, meta=meta, scores=scores, names=names, regex=regex, files=files, file.regex=file.regex, file.cols=file.cols, top=top, cells.use=cells.use,
        groups=groups, group_stat=dot_color)

    # Save levels for ordering
    cells = rownames(x)
    if(reorder == FALSE){
        feats = rev(colnames(x))
    } else {
        feats = colnames(x)[rev(order(apply(x, 2, which.max), -1*apply(x, 2, max)))]
    }
    
    if(coord_flip == TRUE){
        cells = rev(cells)
	feats = rev(feats)
    }
        
    # Re-scale dot size and color
    if(rescale == TRUE){
        x = as.data.frame(scale(x, center=F, scale=sapply(x, max)))
	y = as.data.frame(scale(y, center=F, scale=sapply(y, max)))
    }
    
    # Convert to long format
    d = x %>% rownames_to_column('Group') %>% gather(Feature, Size, -Group)
    y = y %>% rownames_to_column('Group') %>% gather(Feature, Color, -Group)
    d$Color = y$Color
    
    # Re-order data
    d$Group = factor(d$Group, levels=cells)
    d$Feature = factor(d$Feature, levels=feats)
    
    # Dot plot
    p = ggplot(d, aes(x=Group, y=Feature, size=Size, fill=Color)) +
        geom_point(color='black', pch=21, stroke=.25) +
	scale_size_area(dot_size, max_size=max_size) +
	#scale_fill_gradientn(dot_color, colours=brewer.pal(9,'Blues')) +
	scale_fill_gradientn(dot_color, colours=material.heat(8)) +
	theme_cowplot(font_size=font_size) +
	theme(axis.title=element_blank(), panel.grid.major=element_line(colour='black'), axis.text.x=element_text(angle=90, hjust=1, vjust=.5)) + panel_border() +
	background_grid(major='xy')
    
    if(coord_flip == TRUE){p = p + coord_flip()}

    if(!is.null(out)){save_plot(p, file=out, nrow=nrow, ncol=ncol)}
    
    return(p)
}


plot_violin = function(seur=NULL, names=NULL, scores=NULL, data=NULL, meta=NULL, regex=NULL, files=NULL, file.regex=NULL, file.cols=NULL, top=NULL, type='mean', group_by=NULL, color_by=NULL, pt.size=.25,
	               do.facet=FALSE, facet_by=NULL, facet_formula=NULL, facet_scales='free_y', ymin=0, ymax=1, do.scale=FALSE, num_col='auto',
                       ident=TRUE, cells.use=NULL, do.title=TRUE, do.legend=FALSE, xlab='Cell Type', ylab='log2(TPM)', out=NULL, nrow=1.5, ncol=1.5, legend.title='Group',
		       coord_flip=FALSE, alpha=.5, order=NULL, font_size=10){
    
    # Initialize plots
    ps = list()

    # Get facet formula
    if(is.null(facet_formula)){
    if(do.facet == FALSE){
        facet_formula = ifelse(is.null(facet_by), '~ .', 'Facet ~ .')
    } else {
        do.title = FALSE
        facet_formula = ifelse(is.null(facet_by), 'Feature ~ .', 'Feature ~ Facet + .')
    }
    } else {facet_formula = as.formula(facet_formula)}
    
    # Fix input arguments
    if(is.null(group_by)){group_by = seur@ident}
    if(is.null(color_by)){color_by = group_by}
    if(is.null(facet_by)){facet_by = rep('', ncol(seur@data))}
    if(is.null(cells.use)){cells.use = colnames(seur@data)}
    if(is.null(out)){alpha=1} else {alpha=alpha}
    
    # Plot data
    d = data.frame(Group=as.factor(group_by), Color=as.factor(color_by), Facet=as.factor(facet_by), row.names=colnames(seur@data))
    d = d[cells.use,,drop=F]
    if(coord_flip == TRUE){d$Group = factor(d$Group, levels=rev(levels(d$Group)))}
    
    # Cell scores
    scores = score_cells(seur=seur, data=data, meta=meta, scores=scores, names=names, regex=regex, files=files, top=top, file.regex=file.regex, file.cols=file.cols, cells.use=cells.use)
    scores = scores[cells.use,,drop=F]
    d = cbind.data.frame(d, scores)
    
    # Fix NAs
    d = d[!is.na(d$Facet),,drop=F]
    
    # Scale data
    j = sapply(d, function(a) !is.factor(a))
    d[,j] = apply(d[,j,drop=F], 2, function(a) qtrim(a, qmin=ymin, qmax=ymax))
    
    # Facet data
    if(do.facet == TRUE){
	d = gather(d, Feature, Value, -Group, -Color, -Facet)
    }
    
    # Violin plots
    for(col in setdiff(colnames(d), c('Group', 'Color', 'Facet', 'Value'))){

        # Convert to numeric?
	if(!is.character(d[,col])){d[,col] = as.numeric(d[,col])}
        
        # Facet if necessary
        if(do.facet == TRUE){
	    p = ggplot(data=d, aes_string(x='Group', y='Value', fill='Color'))
	} else {
	    p = ggplot(data=d, aes_string(x='Group', y=col, fill='Color'))
	}
	
	# Make violin plot
	p = p +
	    geom_point(position=position_jitterdodge(dodge.width=0.6, jitter.width=2.5), size=pt.size, show.legend=F) +
	    geom_violin(scale='width', alpha=alpha, size=.25) +
	    scale_fill_manual(values=set.colors) + theme_cowplot(font_size=font_size) +
	    xlab(xlab) + ylab(ylab) + labs(fill=legend.title) +
	    stat_summary(fun.y=mean, fun.ymin=mean, fun.ymax=mean, geom='crossbar', width=.5, show.legend=F, size=.25) +
	    theme(axis.text.x = element_text(angle = 45, hjust = 1))

	if(do.title == TRUE){
	    p = p + ggtitle(col)
	}

	if(do.legend == FALSE){
	    p = p + guides(fill=FALSE)
	}

	if(coord_flip == TRUE){
	    p = p + coord_flip()
	}

	if(facet_formula != '~ .'){
	    p = p + facet_grid(as.formula(facet_formula), scales=facet_scales)
	}
	
	ps[[col]] = p
    }

    if(num_col == 'auto'){
        num_col = ceiling(sqrt(length(ps)))
    }
    ps = make_compact(ps, num_col=num_col)
    p = plot_grid(plotlist=ps, ncol=num_col)
    if(is.null(out)){
        p
    } else {
        save_plot(file=out, p, nrow=nrow, ncol=ncol)
    }
}


plot_feats = function(...){plot_tsne(...)}

plot_pcs = function(seur, pcs=NULL, ...){
    if(is.null(pcs)){pcs = 1:seur@data.info$num_pcs[[1]]}
    pcs = seur@pca.rot[,pcs]
    plot_tsne(seur, scores=pcs, ...)
}

plot_clusters = function(seur, ...){
    clusters = sort(grep('Cluster', colnames(seur@data.info), value=T))
    clusters = sapply(seur@data.info[,clusters], function(a){droplevels(as.factor(a))})
    plot_tsne(seur, scores=clusters, ...)
}


matrix_barplot = function(data, group_by=NULL, pvals=NULL, pvals2=NULL, xlab='', ylab='Frequency', value='mean', error='se', legend.title='Groups', colors='Paired',
                          out=NULL, nrow=1.5, ncol=1.5, coord_flip=FALSE, sig_only=F, do.facet=F){
    
    # Plot barplot of [M x N] matrix
    # x-axis = matrix columns (e.g. cell types)
    # y-axis = matrix values (e.g. frequencies)
    # fill = matrix rows (e.g. samples) or groups (e.g. conditions)
    
    # Arguments:
    # group.by = the group of each row
    # pvals = [G x N] matrix of p-values for each group and column
    # error = sd, se, or none
    
    require(tidyverse)
    require(data.table)
    require(ggsignif)
    
    # Groups (default = rows)
    if(is.null(group_by)){group_by = rownames(data)}
    if(nlevels(group_by) == 0){group_by = as.factor(group_by)}
    
    # Select significant comparisons
    if(sig_only == TRUE){
        if(is.null(pvals2)){j = apply(pvals, 2, min) <= .05} else {j = apply(pvals, 2, min) <= .05 | apply(pvals2, 2, min) <= .05}
	if(sum(j) == 0){return(NULL)}
	data = data[,j,drop=F]
	pvals = pvals[,j,drop=F]
    }
        
    # Construct input data
    names = colnames(data)
    data = data.frame(group=group_by, data)
    group_levels = levels(group_by)
    colnames(data)[2:ncol(data)] = names
    data = as.data.table(gather_(data, 'x', 'y', setdiff(colnames(data), 'group')))

    # Value function
    if(value == 'mean'){vf = mean} else if(value == 'median'){vf = median} else {stop()}
    
    # Error function
    se = function(x, na.rm=T){sd(x, na.rm=na.rm)/sqrt(length(x))}    
    if(error == 'sd'){ef = sd} else if(error == 'se'){ef = se} else {ef = function(x){0}}

    # Estimate error bars
    data = data[,.(u=vf(y, na.rm=T), s=ef(y, na.rm=T)),.(group, x)]
    data$x = factor(data$x, levels=names)
    
    # Add p-values 1
    if(!is.null(pvals)){
        pvals = as.data.frame(pvals) %>% rownames_to_column('group') %>% gather(x, pval, -group) %>% as.data.table()
	setkeyv(data, c('x', 'group'))
	setkeyv(pvals, c('x', 'group'))
	data = merge(data, pvals, all=T)
	data$lab1 = ifelse(data$pval <= .001, '0', ifelse(data$pval <= .05, '1', '2'))
	data$text1 = ifelse(data$lab1 != '2', '*', '-')
    }

    # Add p-values 2
    if(!is.null(pvals2)){
        pvals2 = as.data.frame(pvals2) %>% rownames_to_column('group') %>% gather(x, pval2, -group) %>% as.data.table()
	setkeyv(data, c('x', 'group'))
	setkeyv(pvals2, c('x', 'group'))
	data = merge(data, pvals2, all=T)
	data$lab2 = ifelse(data$pval2 <= .001, '0', ifelse(data$pval2 <= .05, '1', '2'))
	data$text2 = ifelse(data$lab2 != '2', '*', '-')
    }
    
    data$group = factor(data$group, levels=group_levels)

    # Get colors
    if(length(colors) == 1){colors = disc.colors(length(group_levels))}
    
    # Plot data
    p = ggplot(data) + 
        geom_bar(aes(x=x, y=u, fill=group), color='0', size=.25, stat='identity', position=position_dodge(.9)) +
        geom_errorbar(aes(x=x, ymin=u-s, ymax=u+s, fill=group), stat='identity', position=position_dodge(.9), width=.25) +
        scale_fill_manual(values=colors, name=legend.title) + xlab(xlab) + ylab(ylab) +
	scale_color_manual('', values=c('#000000', '#999999', '#cccccc'), guide='none')
    
    # Facet wrap
    if(do.facet == TRUE){
        p = p + facet_grid(group ~ ., scales='free')
    }

    dy = max(data$u + data$s, na.rm=T)*.01
    if(coord_flip == FALSE){
        p = p + theme(axis.text.x = element_text(angle = 45, hjust = 1))
	if(!is.null(pvals)){p = p + geom_text(aes(x=x, y=u+s+dy, label=text1, color=lab1, group=group), hjust='left', vjust=0, size=5, angle=0, position=position_dodge(.9))}
	if(!is.null(pvals2)){p = p + geom_text(aes(x=x, y=u+s+dy, label=text2, color=lab2, group=group), hjust='right', vjust=0, size=5, angle=0, position=position_dodge(.9))}
    } else {
        p = p + coord_flip()
	if(!is.null(pvals)){p = p + geom_text(aes(x=x-.15, y=u+s+dy, label=text1, color=lab1, group=group), hjust='center', vjust=1, size=5, angle=90, position=position_dodge(.9))}
	if(!is.null(pvals2)){p = p + geom_text(aes(x=x+.15, y=u+s+dy, label=text2, color=lab2, group=group), hjust='center', vjust=1, size=5, angle=90, position=position_dodge(.9))}
    }
    
    # Save plot
    if(!is.null(out)){save_plot(plot=p, filename=out, nrow=nrow, ncol=ncol)}
    p
}


plot_volcano = function(fcs, pvals, labels=NULL, color_by=NULL, facet_by=NULL, lab.x=c(-1, 1), max_pval=.05, lab.n=0, lab.p=0, lab.size=5, do.repel=TRUE, pval_floor=-Inf,
                        font.size=11, legend.title='Groups', out=NULL, nrow=1.5, ncol=1.5, xlab='Fold change', ylab='-log10(pval)', palette=NULL, ret.labs=FALSE, do.log=T){
    
    # Volcano plot with automatic labeling:
    # best p-values in region lab.x (n = lab.n)
    # best p-values globally (n = lab.p)
    
    # Make plot data
    if(is.null(color_by)){color_by = rep('Group', length(fcs))}
    if(is.null(facet_by)){facet_by = rep('Group', length(fcs))}
    pvals[pvals < pval_floor] = pval_floor
    if(do.log == TRUE){pvals = -log10(pvals)}
    data = data.frame(x=fcs, y=pvals, Color=color_by, Facet=facet_by, stringsAsFactors=F)
    data$Facet = as.factor(data$Facet)
    
    if(!is.null(labels)){        
        for(facet in unique(data$Facet)){
		    
	    # Select facet data
	    i = which(data$Facet == facet & 10**(-data$y) <= max_pval)
	    di = data[i,]
	    
	    # Label points < lab.x
	    breaks = seq(from=min(di$x, na.rm=T), to=lab.x[[1]], length.out=10)
	    groups = cut(di$x, breaks=breaks, include.lowest=TRUE)
	    j1 = as.numeric(simple_downsample(cells=1:nrow(di), groups=groups, ngene=di$y, total_cells=as.integer(lab.n/2)))
	    
	    # Label points > lab.x
	    breaks = seq(from=lab.x[[2]], to=max(di$x, na.rm=T), length.out=10)
	    groups = cut(di$x, breaks=breaks, include.lowest=TRUE)
	    j2 = as.numeric(simple_downsample(cells=1:nrow(di), groups=groups, ngene=di$y, total_cells=as.integer(lab.n/2)))
	    
	    # Label best global p-values
	    j3 = which(order(-1*di$y) <= lab.p)
	    
	    # Set labels
	    j = sort(unique(c(j1, j2, j3)))
	    data[i[j], 'labels'] = TRUE
	}
    } else {
        data$labels = FALSE
    }	
    
    # Set labels
    data$labels = ifelse(data$labels, labels, '')
    
    # Make volcano plot
    p = ggplot(data, aes(x=x, y=y)) +
        geom_point(aes(colour=Color)) +
	theme_cowplot(font_size=font.size) +
	xlab(xlab) +
	ylab(ylab)
    
    # Add labels
    if(do.repel == TRUE){
        p = p + geom_text_repel(aes(label=labels), size=lab.size, segment.color='#cccccc')
    } else {
        p = p + geom_text(aes(label=labels), size=lab.size)
    }
    
    # Add color scale
    if(is.numeric(data$Color)){
        if(is.null(palette)){palette = colorRampPalette(rev(brewer.pal(7, 'RdBu')))(100)}
        p = p + scale_colour_distiller(palette=palette)
    } else {
        if(is.null(palette)){palette = desat(set.colors, .5)}
        p = p + scale_colour_manual(values=palette)
    }
    if(all(color_by == 'Group')){p = p + theme(legend.position='none')}
        
    # Facet wrap
    if(nlevels(data$Facet) > 1){
        print('Faceting')
        p = p + facet_wrap(~ Facet, scales='free') +
	    theme(axis.line = element_line(colour = "black"),
	    panel.grid.major = element_blank(),
	    panel.grid.minor = element_blank(),
	    panel.border = element_blank(),
	    panel.background = element_blank(),
	    strip.background = element_blank())
	    
    }

    # Save to file
    if(!is.null(out)){save_plot(plot=p, filename=out, nrow=nrow, ncol=ncol)}
    if(ret.labs){as.character(na.omit(data$labels))} else {p}
}


plot_volcanos = function(markers, color_by=NULL, outdir='volcano'){
    
    # Create output directory
    if(!file.exists(outdir)){dir.create(outdir)}
    if(!is.null(color_by) & (nrow(markers) != length(color_by))){stop()}
    
    # Split markers by contrast
    m = split(markers, markers$contrast)
    q = split(color_by, markers$contrast)
    
    # Make each volcano plot
    for(name in names(m)){
        out = gsub(':', '.', paste0(outdir, '/', name, '.volcano.png'))
	print(c(name, out))
        plot_volcano(m[[name]]$coefD, m[[name]]$pvalD, labels=m[[name]]$gene, color_by=q[[name]], lab.x=c(-.5, .5), max_pval=.05, lab.n=100, lab.p=20, lab.size=3, out=out, nrow=2, ncol=2)	
    }
}


simple_scatter = function(x, y, lab=NA, col=NULL, col.title='', size=NULL, size.title='', lab.use=NULL, lab.near=0,  lab.n=0, lab.g=0, groups=NULL, lab.size=4, lab.type='up', palette=NULL,
                          xlab=NULL, ylab=NULL, out=NULL, nrow=1, ncol=1, min_size=1, max_size=3, xskip=c(0,0), yskip=c(0,0), xlim=NULL, ylim=NULL, alpha=1){

    require(ggplot2)
    require(ggrepel)
    require(cowplot)
    require(wordspace)

    if(is.null(col)){col = rep('', length(x))}
    if(is.null(size)){size = rep(1, length(x))}
    d = data.frame(x=x, y=y, lab=lab, col=col, size=size, flag='', stringsAsFactors=FALSE)
    i.lab = !is.na(d$lab)
    di = d[i.lab,]
    
    if(is.null(xlab)){xlab = deparse(substitute(x))}
    if(is.null(ylab)){ylab = deparse(substitute(y))}
    
    if(lab.n > 0 | lab.g > 0){

        i = c()
	
	if('up' %in% lab.type | 'down' %in% lab.type){

            # get breaks
	    if(!is.null(groups)){groups.use = groups} else {
	        breaks = seq(from=min(di$x, na.rm=T), to=max(di$x, na.rm=T), length.out=min(20, lab.n))
	        groups.use = cut(di$x, breaks=breaks, include.lowest=TRUE)
		groups.use[xskip[[1]] <= di$x & di$x <= xskip[[2]]] = NA
	    }
	    
	    # get cells
	    if('up' %in% lab.type){
	        i = c(i, as.numeric(simple_downsample(cells=1:nrow(di), groups=groups.use, ngene=di$y, total_cells=lab.n)))
		i = c(i, order(-1*di$y)[1:lab.g])
	    }
	    if('down' %in% lab.type){
	        i = c(i, as.numeric(simple_downsample(cells=1:nrow(di), groups=groups.use, ngene=-1*di$y, total_cells=lab.n)))
		i = c(i, order(di$y)[1:lab.g])
	    }
	}
	
	if('right' %in% lab.type | 'left' %in% lab.type){

	    # get breaks
	    if(!is.null(groups)){groups.use = groups} else {
	        breaks = seq(from=min(di$y, na.rm=T), to=max(di$y, na.rm=T), length.out=min(20, lab.n))
	        groups.use = cut(di$y, breaks=breaks, include.lowest=TRUE)
		groups.use[yskip[[1]] <= di$y & di$y <= yskip[[2]]] = NA
	    }
	    
	    # get cells
	    if('right' %in% lab.type){
	        i = c(i, as.numeric(simple_downsample(cells=1:nrow(di), groups=groups.use, ngene=di$x, total_cells=lab.n)))
		i = c(i, order(-1*di$x)[1:lab.g])
	    }
	    
	    if('left' %in% lab.type){
	        i = c(i, as.numeric(simple_downsample(cells=1:nrow(di), groups=groups.use, ngene=-1*di$x, total_cells=lab.n)))
		i = c(i, order(di$x)[1:lab.g])
	    }
	}
	di[unique(i), 'flag'] = 'lab.n'
    }
    d[i.lab,] = di
    
    if(!is.null(lab.use)){
        
        # label neighbors
	if(lab.near > 0){
	    u = as.matrix(d[, c('x','y')])
	    v = as.matrix(d[lab %in% lab.use, c('x','y')])
	    i = unique(sort(unlist(apply(dist.matrix(u,v,skip.missing=TRUE,method='euclidean'), 2, order)[1:(lab.near + 1),])))
	    d$flag[i] = 'lab.near'
	}
	
        # label points
        d$flag[d$lab %in% lab.use] = 'lab.use'
    }
    
    d$lab[d$flag == ''] = ''
    d = d[order(d$flag),]
    d$flag = factor(d$flag, levels=c('', 'lab.n', 'lab.use', 'lab.near'), ordered=T)
        
    if(all(col == '')){d$col = d$flag}
    
    # plot labeled points last
    d = d[order(d$col),]
    i = is.na(d$col) | d$col == ''
    d = rbind(d[i,], d[!i,])
        
    p = ggplot(d, aes(x=x, y=y)) +
        geom_point(aes(colour=col, size=size), alpha=alpha, stroke=0) +
	geom_text_repel(aes(label=lab), size=lab.size, segment.color='grey') +
	theme_cowplot() + xlab(xlab) + ylab(ylab)
    
    if(all(size == 1)){p = p + scale_size(guide = 'none', range=c(min_size, max_size))} else {p = p + scale_size(name=size.title, range=c(min_size, max_size))}

    if(!is.null(xlim)){p = p + xlim(xlim)}
    if(!is.null(ylim)){p = p + ylim(ylim)}
    
    if(!is.null(palette)){
        p = p + scale_colour_manual(name=col.title, values=palette, na.value='#eeeeee', breaks=levels(as.factor(d$col)))
    } else {
        if(!is.numeric(d$col)){
	    p = p + scale_colour_manual(name=col.title, values=c('lightgrey', 'black', 'red', 'pink')) + theme(legend.position='none')
	} else {
	    p = p + scale_colour_gradientn(name=col.title, colors=material.heat(100), na.value='#eeeeee')
	}
    }
    
    if(!is.null(out)){save_plot(plot=p, filename=out, nrow=nrow, ncol=ncol)}

    return(p)
}
