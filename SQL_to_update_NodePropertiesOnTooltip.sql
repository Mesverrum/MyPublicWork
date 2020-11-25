--ensures all node properties have been added to the table
insert into [CustomPropertyUsage]
select targettable, name, 'IsForEntityDetail', 1
from [CustomPropertyMetadata]
where targettable = 'NodesCustomProperties'
and name not in (select distinct name from [CustomPropertyUsage] where targettable = 'NodesCustomProperties' and usage = 'IsForEntityDetail' )

--ensures only the 5 or fewer properties I want show on the tooltip
update [CustomPropertyUsage]
set allowed = 0
where targettable = 'NodesCustomProperties'
and usage = 'IsForEntityDetail'
and allowed = 1
--below should be your list of property names you want to keep
and name not in ('MyCustomProperty1','MyCustomProperty2','MyCustomProperty3','MyCustomProperty4','MyCustomProperty5')
