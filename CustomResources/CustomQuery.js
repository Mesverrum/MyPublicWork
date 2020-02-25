SW.Core.Resources = SW.Core.Resources || {};
SW.Core.Resources.CustomQuery = SW.Core.Resources.CustomQuery || {};

(function(cq) {
    var settings = {};

    var baseSettings = {
        initialPage: 0,
        rowsPerPage: 5,
        searchTextBoxId: '',
        searchButtonId: '',
        allowSort: true,
        allowPaging: true,
        onLoad: null,
        autoHide: false,
        showLoadingControl: true,
        onHide: onAutoHide
    };

    var baseColumnSettings = {
        header: null,
        formatter: null,
        cellCssClassProvider: null,
        headerCssClass: null,
        isHtml: false,
        allowSort: true
    };
    
    var PageManager = function(pageIndex, pageSize, pagingAllowed) {
        this.currentPageIndex = pageIndex;
        this.rowsPerPage = pageSize;
        this.pagingAllowed = pagingAllowed;
        this.totalRowsCount = 0;

        this.startItem = function() {
            return (this.rowsPerPage * this.currentPageIndex) + 1;
        };

        this.lastItem = function() {
            // If paging allowed: Ask for rowsPerPage + 1 rows so we can detect if this is the last page.
            // If paging disabled: Ask for rowPagePage rows exactly.
            return (this.rowsPerPage * (this.currentPageIndex + 1)) + (this.pagingAllowed ? 1 : 0);
        };
        
        this.numberOfPages = function () {
            return Math.ceil(this.totalRowsCount / this.rowsPerPage);
        };

        this.withRowsClause = function() {
           if (!this.pagingAllowed) {
               return "";
           }
           return "\n WITH ROWS " + this.startItem() + " TO " + this.lastItem() + this.withTotalRowsClause();
        };

        this.withTotalRowsClause = function() {
            return "\n WITH TOTALROWS";
        };

        this.isLastPage = function(rowCount) {
            // We asked for rowsPerPage + 1 rows.  If more than rowsPerPage rows 
            // got returned, we know this isn't the last page.
            return rowCount <= this.rowsPerPage;
        };
    };

    var generateColumnInfo = function(uniqueId, columns) {
        var columnInfo = [];
        var indexLookup = {};

        // Map column text to its index.
        $.each(columns, function(index, name) {
            indexLookup[name] = index;
            columnInfo[index] = { };
        });
        
        // Lookup each column's formatting information.
        $.each(columns, function(index, name) {
            var columnSettings = getResultColumnSettings(uniqueId, name);
            
            columnInfo[index] = columnSettings;
            columnInfo[index].name = name;
            if (columnInfo[index].header == null) {
                columnInfo[index].header = ((name != '') && (name.substring(0, 1) !== '_')) ? name : null;
            }
            if (columnInfo[index].formatter == null) {
                // This is here to get formatters defined in "old way". New way is to use column configuration.
                columnInfo[index].formatter = getCustomFormatter(uniqueId, name);
            }

            var otherColumnIndex = getReferencedColumnIndex(name, '_IconFor_', indexLookup);
            if (otherColumnIndex != null) {
                columnInfo[otherColumnIndex].iconColumn = index;
            }
            
            otherColumnIndex = getReferencedColumnIndex(name, '_LinkFor_', indexLookup);
            if (otherColumnIndex != null) {
                columnInfo[otherColumnIndex].linkColumn = index;
            }
            otherColumnIndex = getReferencedColumnIndex(name, '_StyleFor_', indexLookup);
            if (otherColumnIndex != null) {
                columnInfo[otherColumnIndex].styleColumn = index;
            }			
        });
        
        return columnInfo;
    };

    var getReferencedColumnIndex = function(name, prefix, columnIndexLookup) {
        var re = new RegExp('^' + prefix + '(.+)$', 'i');
        var match = name.match(re);
        return match ? columnIndexLookup[match[1]] : null;
    };

    // This is here to get formatters defined in "old way". New way is to use column configuration.
    var getCustomFormatter = function(uniqueId, columnName) {
        if (typeof (settings[uniqueId].customFormatters) === "undefined")
            return null;
        
        if (typeof (settings[uniqueId].customFormatters[columnName]) == "function") {
            return settings[uniqueId].customFormatters[columnName];
        }
        
        return null;
    };
    
    var getResultColumnSettings = function(uniqueId, columnName) {
        var columnSettings = getUserDefinedColumnSettings(uniqueId, columnName);
        if (columnSettings != null)
            return columnSettings;

        // make copy of base settings
        return $.extend({}, baseColumnSettings);
    };

    var getUserDefinedColumnSettings = function(uniqueId, columnName) {
        if (typeof (settings[uniqueId].columnSettings) === "undefined")
            return null;
        
        if (typeof (settings[uniqueId].columnSettings[columnName]) !== "undefined") {
            return $.extend({}, baseColumnSettings, settings[uniqueId].columnSettings[columnName]);
        }
        
        return null;
    };
        
    var renderCell = function(uniqueId, cellValue, rowArray, cellInfo) {
        var cell = $('<td/>');
        cell.addClass('column' + cellInfo.cellIndex);
        if (cellValue == null)
        {
           cellValue = "";
        }
        else if (Date.isInstanceOfType(cellValue)) {
            cellValue = cellValue.localeFormat(Sys.CultureInfo.CurrentCulture.dateTimeFormat.ShortDatePattern) + " " + cellValue.localeFormat(Sys.CultureInfo.CurrentCulture.dateTimeFormat.LongTimePattern); 
        }

        if (cellInfo.cellCssClassProvider != null) {
            cell.addClass(cellInfo.cellCssClassProvider(cellValue, rowArray, cellInfo));
        }

        if (cellInfo.formatter != null) {
            cellValue = cellInfo.formatter(cellValue, rowArray, cellInfo);
        }
        
        if (cellInfo.iconColumn) {
            $('<img/>').attr('src', rowArray[cellInfo.iconColumn]).appendTo(cell);
        }

        var element;
        if (cellInfo.linkColumn) {
            element = $('<a/>').attr('href', rowArray[cellInfo.linkColumn]);
        }else if (cellInfo.styleColumn){		
			element = $('<span/>').attr('style', rowArray[cellInfo.styleColumn]);
		}else {
            element = $('<span/>');
        }

        if (cellInfo.isHtml) {
            element.html(cellValue);
        } else {
            element.text(cellValue);
        }
        element.appendTo(cell);

        return cell;
        
    };

    var getSearchText = function(uniqueId) {
        var searchText = '';
        if (typeof (settings[uniqueId].searchTextBoxId) !== "undefined" && settings[uniqueId].searchTextBoxId != '') {
            searchText = $('#' + settings[uniqueId].searchTextBoxId).val();
        }
        
        return searchText;
    };

    var getPager = function(uniqueId) {
        return $('#Pager-' + uniqueId);
    };
    
    var getCurrentPageSize = function (uniqueId) {
        var pager = getPager(uniqueId);
        var pageSize = pager.find('.pageSize').val();
        if (typeof (pageSize) === "undefined" || pageSize == '' || pageSize <= 0) {
            pageSize = settings[uniqueId].rowsPerPage;
        }
        return pageSize;
    };

    var updatePagerControls = function(uniqueId, pageManager, rowCount) {
        var pager = getPager(uniqueId);
        var pageIndex = pageManager.currentPageIndex;
        var html = [];

        var showAllText = '@{R=Core.Strings;K=WEBJS_TM1_CUSTOMQUERY_SHOWALL;E=js}'; //Show all
        var displayingObjectsText = '@{R=Core.Strings;K=WEBJS_AK0_54;E=js}'; //Displaying objects {0} - {1} of {2}
        var pageXofYText = '@{R=Core.Strings;K=WEBJS_JT0_2;E=js}'; //Page {0} of {1}
        var itemsOnPageText = '@{R=Core.Strings;K=WEBJS_JT0_3;E=js}'; // Items on page
        
        var style = 'style="vertical-align:middle"';
        var firstImgRoot = '/Orion/images/Arrows/button_white_paging_first';
        var previousImgRoot = '/Orion/images/Arrows/button_white_paging_previous';
        var nextImgRoot = '/Orion/images/Arrows/button_white_paging_next';
        var lastImgRoot = '/Orion/images/Arrows/button_white_paging_last';

        var showAll = showAllText;
        var haveLinks = false;

        var startHtml;
        var endHtml;
        var contents;

        if (pageIndex > 0) {
            startHtml = '<a href="#" class="firstPage NoTip">';
            contents = String.format('<img src="{0}.gif" {1}/>', firstImgRoot, style);
            endHtml = '</a>';
            
            html.push(startHtml + contents + endHtml);
            html.push(' | ');

            startHtml = '<a href="#" class="previousPage NoTip">';
            contents = String.format('<img src="{0}.gif" {1}/>', previousImgRoot, style);
            endHtml = '</a>';

            html.push(startHtml + contents + endHtml);
            html.push(' | ');
            
            haveLinks = true;
        } else {
            startHtml = '<span style="color:#646464;">';
            contents = String.format('<img src="{0}_disabled.gif" {1}/>', firstImgRoot, style);
            endHtml = '</span>';
            
            html.push(startHtml + contents + endHtml);
            html.push(' | ');

            startHtml = '<span style="color:#646464;">';
            contents = String.format('<img src="{0}_disabled.gif" {1}/>', previousImgRoot, style);
            endHtml = '</span>';

            html.push(startHtml + contents + endHtml);
            html.push(' | ');
        }

        startHtml = String.format(pageXofYText, '<input type="text" class="pageNumber SmallInput" value="' + (pageManager.currentPageIndex + 1) + '" />', pageManager.numberOfPages());

        html.push(startHtml);
        html.push(' | ');
        
        if (!pageManager.isLastPage(rowCount)) {
            startHtml = '<a href="#" class="nextPage NoTip">';
            contents = String.format('<img src="{0}.gif" {1}/>', nextImgRoot, style);
            endHtml = '</a>';
            
            html.push(startHtml + contents + endHtml);
            html.push(' | ');
            
            startHtml = '<a href="#" class="lastPage NoTip">';
            contents = String.format('<img src="{0}.gif" {1}/>', lastImgRoot, style);
            endHtml = '</a>';

            html.push(startHtml + contents + endHtml);
            html.push(' | ');

            haveLinks = true;
        } else {
            startHtml = '<span style="color:#646464;">';
            contents = String.format('<img src="{0}_disabled.gif" {1}/>', nextImgRoot, style);
            endHtml = '</span>';
            
            html.push(startHtml + contents + endHtml);
            html.push(' | ');

            startHtml = '<span style="color:#646464;">';
            contents = String.format('<img src="{0}_disabled.gif" {1}/>', lastImgRoot, style);
            endHtml = '</span>';

            html.push(startHtml + contents + endHtml);
            html.push(' | ');
        }

        contents = itemsOnPageText;
        endHtml = '<input type="text" class="pageSize SmallInput" value="' + pageManager.rowsPerPage + '" />';

        html.push(contents + endHtml);
        html.push(' | ');

        html.push('<a href="#" class="showAll NoTip">' + showAll + '</a>');
        
        html.push(' | ');
        
        html.push('<div class="ResourcePagerInfo">');
        startHtml = String.format(displayingObjectsText, pageManager.startItem(), Math.min(pageManager.lastItem()-1, pageManager.totalRowsCount), pageManager.totalRowsCount);
        html.push(startHtml);
        html.push('</div>');

        pager.empty().append(html.join(' '));
        var method = haveLinks ? 'show' : 'hide';
        pager[method]();
       
        pager.find('.firstPage').click(function () {
            createTableFromQuery(uniqueId, 0, pageManager.rowsPerPage);
            return false;
        });
        
        pager.find('.previousPage').click(function() {
            createTableFromQuery(uniqueId, pageIndex - 1, pageManager.rowsPerPage);
            return false;
        });

        pager.find('.nextPage').click(function() {
            createTableFromQuery(uniqueId, pageIndex + 1, pageManager.rowsPerPage);
            return false;
        });
        
        pager.find('.lastPage').click(function () {
            createTableFromQuery(uniqueId, pageManager.numberOfPages()-1, pageManager.rowsPerPage);
            return false;
        });

        pager.find('.showAll').click(function() {
            // We don't have a good way to show all.  We'll show 1 million and 
            // accept that there's an issue if there are more than that :)
            createTableFromQuery(uniqueId, 0, 1000000);
            return false;
        });

        var changePageSize = function() {
            createTableFromQuery(uniqueId, 0, getCurrentPageSize(uniqueId));
        };
        pager.find('.pageSize').change(function () {
            changePageSize();
        });
        pager.find('.pageSize').keydown(function (e) {
            if (e.keyCode == 13) {
                changePageSize();
                return false;
            }
            return true;
        });
        
        var changePageNumber = function () {
            var pageNumber = pager.find('.pageNumber').val();
            if (pageNumber <= 0) {
                pageNumber = 1;
            } else if (pageNumber > pageManager.numberOfPages()) {
                pageNumber = pageManager.numberOfPages();
            }
            createTableFromQuery(uniqueId, pageNumber-1, pageManager.rowsPerPage);
        };
        pager.find('.pageNumber').change(function () {
            changePageNumber();
        });
        pager.find('.pageNumber').keyup(function (e) {
            if (e.keyCode == 13) {
                changePageNumber();
                return false;
            }
            return true;
        });
    };

    var determineOrderColumn = function (swql, previousOrderBy, currentOrderBy) {
        // if user applied ordering to the query in UI then use it
        if (typeof (currentOrderBy) !== 'undefined' && currentOrderBy != '') {
            return currentOrderBy;
        }
        // otherwise if the query already has 'order by' clause, leave it as is
        else if (swql.toUpperCase().lastIndexOf("ORDER BY") > -1) {
            return "";
        }

        // this can come from ascx control as default sort option for query
        if (previousOrderBy != '') {
            return previousOrderBy;
        }

        // if no sorting has been specified, then order by the first column
        var swqlUpperCase = swql.toUpperCase();
        var startIndex = swqlUpperCase.indexOf("SELECT") + 6;
        var endIndex = swqlUpperCase.indexOf(",");
        if (endIndex === -1) {
            endIndex = swqlUpperCase.indexOf("FROM");
        }

        if (startIndex >= endIndex) {
            return "1";
        }

        var column = swql.substring(startIndex, endIndex).trim();
        var orderColumnBackspaceIndex = column.indexOf(" ");
        if (orderColumnBackspaceIndex > -1) {
            column = column.substring(0, orderColumnBackspaceIndex);
        }

        return column;
    };

    var applyOrderByToSwql = function (swql, currentOrderBy) {
        // if the sort order isn't specified, just use the query as is
        if (currentOrderBy == '') {
            return swql;
        }

        var swqlUpperCase = swql.toUpperCase();

        var orderbyIndex = swqlUpperCase.lastIndexOf("ORDER BY");
        if (orderbyIndex !== -1) {
            // assume everything after ORDER BY is only ordering columns
            swql = swql.substring(0, orderbyIndex).trim();
        }

        swql += "\n ORDER BY " + currentOrderBy;

        return swql;
    };
    
    var showLoading = function (uniqueId) {
        if (settings[uniqueId].showLoadingControl) {
            $('#Loading-' + uniqueId).show();
        }
    };
    
    var hideLoading = function (uniqueId) {
        $('#Loading-' + uniqueId).hide();
    };
    
    var createTableFromQuery = function (uniqueId, pageIndex, pageSize, currentOrderBy) {
        var nonSearchSwql = $('#SWQL-' + uniqueId).val().trim();
        var swql = nonSearchSwql;
        var searchSwql = $('#SearchSWQL-' + uniqueId).val().trim();
        var errorMsg = $('#ErrorMsg-' + uniqueId);
        var grid = $('#Grid-' + uniqueId);
        var previousOrderBy = $('#OrderBy-' + uniqueId).val();
        var limitation = $('#Limitation-' + uniqueId).val();
        var partialErrorDiv = $('#PartialError-' + uniqueId);
        var searching = false;

        // use search SWQL if search text is defined
        var searchText = getSearchText(uniqueId);
        if (typeof (searchText) !== "undefined" && searchText.trim().length > 0) {
            searching = true;
            swql = searchSwql;
            swql = swql.replace(new RegExp('\\$\\{SEARCH_STRING\\}', 'g'), searchText.trim());
        }
        
        if (swql.length === 0)
        {
            errorMsg.text('@{R=Core.Strings;K=WEBJS_TM1_CUSTOMQUERY_NOQUERY;E=js}').show();            
            return;
        }

        errorMsg.hide();

        currentOrderBy = determineOrderColumn(swql, previousOrderBy, currentOrderBy);
        swql = applyOrderByToSwql(swql, currentOrderBy);
       
        // 0 means to keep whatever page size is set in page size text box
        if (pageSize == 0) {
            pageSize = getCurrentPageSize(uniqueId);
        }
        var pageManager = new PageManager(pageIndex, pageSize, settings[uniqueId].allowPaging);
        swql += pageManager.withRowsClause();
        swql += '\n' + limitation;

        showLoading(uniqueId);
        Information.QueryWithPartialErrors(swql, function (result) {
            var headers = $('tr.HeaderRow', grid);

            // if autoHiding is enabled, there are no data and searching is not active, hide the resource
            if (!searching && settings[uniqueId].autoHide && (result.Data.TotalRows == null || result.Data.TotalRows == 0)) {
                if (typeof (settings[uniqueId].onHide) === "function") {
                    settings[uniqueId].onHide(uniqueId);
                    return;
                }
            }

            pageManager.totalRowsCount = result.Data.TotalRows;

            headers.empty();
            grid.find('tr:not(.HeaderRow)').remove();
            
            var columnInfo = generateColumnInfo(uniqueId, result.Data.Columns);
            $.each(columnInfo, function(colIndex, column) {
                if (column.header !== null) {
                    var headerHtml = $('<div/>').text(column.header).text();
                    var sortArrow = '';
                    
                    var newOrderBy = '[' + column.name + ']';
                    if (newOrderBy == currentOrderBy) {
                        // reverse order on next click
                        var descIndex = newOrderBy.indexOf(" DESC");
                        if (descIndex === -1) {
                            newOrderBy += " DESC";
                        } else {
                            newOrderBy = newOrderBy.substring(0, descIndex);
                        }
                        
                        sortArrow += '&nbsp;<img class="SortArrow" src="/Orion/images/Arrows/Arrow_Ascending.png" />';
                    } else if (currentOrderBy == newOrderBy + ' DESC') {
                        sortArrow += '&nbsp;<img class="SortArrow" src="/Orion/images/Arrows/Arrow_Descending.png" />';
                    }
                    
                    var cell = $('<td/>')
                        .addClass('ReportHeader')
                        .css('text-transform', 'uppercase')
                        .appendTo(headers);
                    
                    if (settings[uniqueId].allowSort && column.allowSort) {
                        cell.addClass("Sortable");
                        cell.click(function() {
                            $('#OrderBy-' + uniqueId).val(newOrderBy);
                            createTableFromQuery(uniqueId, pageIndex, pageManager.rowsPerPage, newOrderBy);
                        });
                        
                        headerHtml += sortArrow;
                    }

                    if (column.headerCssClass != null) {
                        cell.addClass(column.headerCssClass);
                    }

                    cell.html(headerHtml);
                }
            });

            var rowsToOutput = result.Data.Rows.slice(0, pageManager.pagingAllowed ? pageManager.rowsPerPage : pageManager.rowsPerPage = result.Data.Rows.length);

            $.each(rowsToOutput, function(rowIndex, row) {
                var tr = $('<tr/>');

                $.each(row, function(cellIndex, cell) {
                    var info = columnInfo[cellIndex];

                    var cellInfo = $.extend({}, info, {
                        cellIndex: cellIndex,
                        rowIndex: rowIndex
                    });

                    // columns starting with underscore should not be rendered
                    if (info.name.substring(0, 1) !== '_') 
                        renderCell(uniqueId, cell, row, cellInfo).appendTo(tr);
                });
                grid.append(tr);
            });

            updatePagerControls(uniqueId, pageManager, result.Data.Rows.length);
            partialErrorDiv.html(result.ErrorHtml);
            if (typeof (settings[uniqueId].onLoad) === "function") {
                settings[uniqueId].onLoad(rowsToOutput, columnInfo);
            }
            hideLoading(uniqueId);
        }, function (error) {
            errorMsg.text(error.get_message()).show();
            hideLoading(uniqueId);
        });
    };

    var initializeSearch = function (initialSettings) {
        var searchTextBox = null;
        if (typeof (initialSettings.searchTextBoxId) !== "undefined" && initialSettings.searchTextBoxId != '') {
            searchTextBox = $('#' + initialSettings.searchTextBoxId);
        }
        if (typeof (searchTextBox) === "undefined" || searchTextBox == null) {
            // no search box, no search
            return;
        }
        
        var searchButton = null;
        if (typeof(initialSettings.searchButtonId) !== "undefined" && initialSettings.searchButtonId != '') {
            searchButton = $('#' + initialSettings.searchButtonId);
        }

     var triggerSearchFunction = function () {
            var searchText = getSearchText(initialSettings.uniqueId);
            var attrVal = searchButton.attr('src');
            if (attrVal == '/Orion/images/Button.SearchIcon.gif') {
                if (typeof(searchText) != "undefined" && searchText.length > 0) {
                    searchButton.attr('src', '/Orion/images/Button.SearchCancel.gif');
                }
            } else {
                    searchButton.attr('src', '/Orion/images/Button.SearchIcon.gif');
                    searchTextBox.val('');
                }
            createTableFromQuery(initialSettings.uniqueId, settings[initialSettings.uniqueId].initialPage,
                  settings[initialSettings.uniqueId].rowsPerPage);

        };

        // search textbox handler
        searchTextBox.keyup(function (e) {
            if (e.keyCode == 13 || e.keyCode == 27) {
                triggerSearchFunction();
                return false;
            }
			else {
				searchButton.attr('src', '/Orion/images/Button.SearchIcon.gif');
			}
            return true;
        });
        // search button handler
        if (typeof(searchButton) !== "undefined" && searchButton != null) {
            searchButton.click(function() {
                triggerSearchFunction();
                return false;
            });
        }
    };

    function onAutoHide(uniqueId) {
        // hiding resource with customQueryTable by hiding ResourceWrapper element with the same resourceID
        // this method can be overrided via settings.onHide (for example in case you have several customQueryTables 
        // in one resource or when you are using it out of any resource)
        $("div.ResourceWrapper[resourceid='" + uniqueId + "']").hide();
    };

    /*
    Sample of initial settings
    {
        uniqueId: <%= Resource.ID %>,
        initialPage: 0,
        rowsPerPage: <%= Resource.Properties["RowsPerPage"] ?? "5" %>,
        searchTextBoxId: '<%= SearchControl.SearchBoxClientID %>',
        searchButtonId: '<%= SearchControl.SearchButtonClientID %>',
        allowSearch: true,
        autoHide: true,     // automatically hides the resource when there are no data to show
        showLoadingControl: true,   // show loading message on AJAX request
        onLoad: function (rows, columnsInfo) {
            // at this point your table is filled in with new requested data
            // also pager is refreshed with new position, so you can continue 
            // here with further processing if necessary
            // e.g. refresh your custom controls, labels, or hide loader if you use a custom one

            $.each(rows, function (index, row) {
                //you can now go through all rows displayed onthe current page and do what ever you need
            });

            $.each(columnsInfo, function (index, column) {
                //you can now go through all columns and use what you need
            });
        },
        columnSettings: {
            "Name": {
                header: 'header1',
                formatter: function (value) { return '##' + value; },
                cellCssClassProvider: function(value, row, cellInfo) {
                    return 'blabla';
                },
                isHtml: true,
                // even if table is sortable, this column won't be
                // useful in case underlying data type isn't sortable e.g. NTEXT in SQL
                allowSort: false
            },
            "Name2":{
                header: 'header2',
                formatter: function (value, row, cellInfo) { return '##' + value; },
                isHtml: false
            }
        }
    }
    */
    cq.initialize = function (initialSettings) {
		// ensure that resource is initialized only once
		if(settings[initialSettings.uniqueId] !== undefined) {
			return;
		}
        var mergedSettings = $.extend({}, baseSettings, initialSettings);
        settings[initialSettings.uniqueId] = mergedSettings;
        
        if (typeof (mergedSettings.searchTextBoxId) !== "undefined" && mergedSettings.searchTextBoxId != '') {
            initializeSearch(initialSettings);
        }
    };
	
	cq.getSettings = function (uniqueId) {
        return settings[uniqueId];
    };

    cq.refresh = function (uniqueId) {
        createTableFromQuery(uniqueId, settings[uniqueId].initialPage, getCurrentPageSize(uniqueId));
    };

    cq.setQuery = function (uniqueId, query) {
        $('#SWQL-' + uniqueId).val(query);
    };

    cq.setSearchQuery = function (uniqueId, query) {
        $('#SearchSWQL-' + uniqueId).val(query);
    };
})(SW.Core.Resources.CustomQuery);