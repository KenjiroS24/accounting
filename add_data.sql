--create database accounting;
--drop database accounting;

drop schema if exists src cascade;
drop schema if exists archive cascade;

create schema src;
create schema archive;

/*
select * from src.consignment;
select * from src.employees_list;
select * from src.items_list;
select * from src.property_list;
select * from src.v_property_list;
*/

/*
Создание ролей

Содержание скрипта:
	-Таблицы и представления
	src.consignment
	src.employees_list
	src.items_list
	src.property_list
	src.v_property_list
	src.v_statistic
	
	-Последовательность
	src.property_list_inventory_number_seq

	-Вставки строк в вышеуказанные таблицы
	
	-Функции
	src.give_equipment	
	src.take_equipment

Раздача прав пользователю
*/


drop role if exists users;
drop role if exists jun_user;

--Создание роли Юзеров с правом наследования и ограниченным сроком действия пароля
CREATE ROLE users WITH 
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOLOGIN
	NOREPLICATION
	NOBYPASSRLS
	CONNECTION LIMIT -1
	VALID UNTIL '2022-12-01';

create user jun_user with 
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	LOGIN
	NOREPLICATION
	NOBYPASSRLS
	CONNECTION LIMIT -1
	password 'abracadabra24'
	VALID UNTIL '2022-12-01';

--Пригласить в группу пользователя
grant users to jun_user;


--список накладных
create table src.consignment (
	consignment_id int8 primary key generated always as identity,
	number_consignment varchar not null default '',
	receipt_date date not null default now()
);
COMMENT ON TABLE src.consignment IS 'consignment - таблица, в которой хранится документация накладных и дат поступления';
COMMENT ON COLUMN src.consignment.number_consignment IS 'номер накладной, состоит из букв и цифр';
COMMENT ON COLUMN src.consignment.receipt_date IS 'дата поступления';

--список сотрудников
create table src.employees_list (
	employee_id int8 primary key generated always as identity,
	full_name varchar not null,
	department varchar not null default 'Иное'
);
COMMENT ON TABLE src.employees_list IS 'employees_list - список сотрудников';
COMMENT ON COLUMN src.employees_list.full_name IS 'полное имя сотрудника';
COMMENT ON COLUMN src.employees_list.department IS 'название отдела, в котором работает сотрудник';

--список возможных вещей и названия
create table src.items_list (
	items_id int8 primary key generated always as identity,
	title varchar
);
COMMENT ON TABLE src.items_list IS 'items_list - список возможной техники для вставки в property_list';
COMMENT ON COLUMN src.items_list.title IS 'название техники';

--Создание последовательности
CREATE SEQUENCE src.property_list_inventory_number_seq
	NO MINVALUE
	NO MAXVALUE;

--список имущества
create table src.property_list (
	property_id int8 primary key generated always as identity,
	items_id int8 references src.items_list (items_id),
	consignment_id int8 references src.consignment(consignment_id),
	inventory_number int8 not null default nextval('src.property_list_inventory_number_seq'),
	employee_owner int8 null default null references src.employees_list(employee_id),
	state int8 not null default 1--1 - свободно, 2 - занято, 3 - в ремонте, 4 - списано
);
COMMENT ON TABLE src.property_list IS 'property_list - список техники, которая была проведена по накладной и числится в компании';
COMMENT ON COLUMN src.property_list.items_id IS 'ссылка на items_list - ID техники';
COMMENT ON COLUMN src.property_list.consignment_id IS 'ссылка на consignment - ID накладной';
COMMENT ON COLUMN src.property_list.inventory_number IS 'inventory_number - инвентарный номер. Для нумерация используется последовательность';
COMMENT ON COLUMN src.property_list.employee_owner IS 'ссылка на employee_list - ID сотрудника, который закреплен за техникой';
COMMENT ON COLUMN src.property_list.state IS 'ID состояния техники: 1 - свободно, 2 - занято, 3 - в ремонте, 4 - списано';

create or replace view src.v_property_list as 
select pl.property_id, il.title, c.number_consignment, c.receipt_date, 'IZp-' || pl.inventory_number as inventory_number, 
		coalesce(el.full_name, 'n/d') as full_name,
		case when pl.state = 1 then 'Незакреплено за сотрудником(свободно)'
			when pl.state = 2 then 'Закреплено за сотрудником'
			when pl.state = 3 then 'В ремонте'
			when pl.state = 4 then 'Списано'
			else 'n/d state'
		end as state
	from src.property_list as pl
	join src.items_list as il on pl.items_id = il.items_id
	join src.consignment as c on c.consignment_id = pl.consignment_id
	left join src.employees_list as el on el.employee_id = pl.employee_owner;
COMMENT ON VIEW src.v_property_list IS 'v_property_list - представление, позволяющее просмотреть список имущества компании в удобном виде';

create or replace view src.v_statistic as 
with free_part as (
	select title as equp, count(*) as cnt
		from src.v_property_list as v
		where state like 'Незакреплено за сотрудником(свободно)'
	group by title
	order by title
)
--select * from zakrep;
, total as (
select title as equp, count(*) as total_cnt
	from src.v_property_list as v
group by title
order by title
)
select t.equp, t.total_cnt, coalesce(fp.cnt, 0) as free_cnt, t.total_cnt - coalesce(fp.cnt, 0) as busy_cnt
	from total as t
	left join free_part as fp on t.equp = fp.equp;
COMMENT ON VIEW src.v_statistic IS 'v_statistic - статистика по оборудованию. total_cnt - кол-во оборудования всего; free_cnt - кол-во незанятого оборудования; busy_cnt - кол-во занятого оборудования';


insert into src.items_list (title) values
('Сетевой фильтр FinePower Standart 418W (4 розетки)'),
('Сетевой фильтр FinePower Standart 618W (6 розеток)'),
('ПК (Intel i5-9400)'),
('ПК (Intel i3-10100F)'),
('Монитор Loc'),
('Монитор LG'),
('Комплект Мышка+Клавиатура Logitech'),
('Ноутбук Apple MacBook M1'),
('Ноутбук HP 15s');

insert into src.employees_list (full_name, department) values
('Васильев Е.Д.', 'Web-Front-DEV'),
('Ким О.А.', 'Web-Front-DEV'),
('Скворцов С.В.', 'Web-Front-DEV'),
('Попов С.М.', 'Web-Back-DEV'),
('Зимин В.В.', 'Web-Back-DEV'),
('Титов В.А.', 'Web-Back-DEV'),
('Игитов М.А.', 'Andriod-DEV'),
('Андрейчуков Г.Э.', 'Andriod-DEV'),
('Сулейманов А.Т.', 'iOS-DEV'),
('Столыпин Н.Н.', 'iOS-DEV'),
('Алферова М.С.', 'Design'),
('Никитина Е.А.', 'Design');

insert into src.consignment (number_consignment, receipt_date) values
('IZ-456/I', '2022-05-26'),
('IZ-584/I', '2022-05-27'),
('IZ-796/II', '2022-06-01');

insert into src.property_list (items_id, consignment_id, employee_owner, state) values
(1, 1, null, 1),(1, 1, null, 1),(1, 1, null, 1),
(2, 1, null, 1),(2, 1, null, 1),(2, 1, null, 1),(2, 1, null, 1),
(8, 1, null, 1),(8, 1, null, 1),
(9, 1, null, 1),(9, 1, null, 1);

insert into src.property_list (items_id, consignment_id, employee_owner, state) values
(3, 2, null, 1),(3, 2, null, 1),(3, 2, null, 1),(3, 2, null, 1),
(4, 2, null, 1),(4, 2, null, 1),(4, 2, null, 1),(4, 2, null, 1),
(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),(5, 2, null, 1),
(6, 2, null, 1),(6, 2, null, 1),(6, 2, null, 1),(6, 2, null, 1),
(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1),(7, 2, null, 1);


--Пример использования
--select src.give_equipment(1, '{4, 10, 16, 20, 21, 32}'::_int8);

--Закрепить за сотрудником имущество
create or replace function src.give_equipment(_employee_id int8, _property_id _int8)
returns jsonb
language plpgsql
as $function$
declare
p_res jsonb;
p_check jsonb;
p_employee_name varchar;
p_property_title jsonb;

begin 
	
	--Проверка на корректный ID сотрудника
	select full_name into p_employee_name
		from src.employees_list as el 
	where el.employee_id = _employee_id;
	if not found then 
		raise exception 'Некорректный ID сотрудника';
	end if;

	--Проверка на корректные ID имущества
	with s as (
		select unnest(_property_id) as i
	)
	, test as (
		select * from src.property_list as pl
			right join s on s.i = pl.property_id
	)
	select jsonb_agg(i) into p_check
		from test 
	where property_id is null;
	if p_check is not null then
		raise exception 'Несуществующий ID ->> %', p_check
		using hint = 'Проверьте введенный массив _property_id';
	end if;

	--Проверка на возможность записать оборудование на сотрудника
	if exists (
		with s as (
			select unnest(_property_id) as i
		)
		select pl.*, s.*
			from src.property_list as pl
			join s on s.i = pl.property_id
		where pl.state in (2,3,4)
		)
	then 
		raise exception 'Попытка закрепить недоступное оборудование'
			using hint = 'Убедитесь, что оборудование не занято, не списано и не находится в ремонте (state)';
	end if;

	--Закрепление имущества за сотрудником
	update src.property_list as pl
		set employee_owner = _employee_id,
			state = 2
	where pl.property_id = any (_property_id);

	select jsonb_agg(title) into p_property_title
		from src.v_property_list vpl 
	where vpl.property_id = any (_property_id);

	p_res = jsonb_build_object('Закреплено за сотрудником', p_employee_name, 'Оборудование', p_property_title);
	return p_res;

end;
$function$;
COMMENT ON FUNCTION src.give_equipment(int8, _int8) IS 'give_equipment - функция, позволяющая закрепить за сотрудником имущество. На вход принимается ID сотрудника и массив IDs имущества';


--Пример использования
--select src.take_equipment(6, '{14,15}'::_int8);

--Открепить сотрудника от оборудования
create or replace function src.take_equipment(_employee_id int8, _property_id _int8)
returns jsonb
language plpgsql
as $function$
declare
p_res jsonb;
p_employee_name varchar;
p_property_title jsonb;
p_check jsonb;

begin 
	
	--Проверка на корректный ID сотрудника
	select full_name into p_employee_name
		from src.employees_list as el 
	where el.employee_id = _employee_id;
	if not found then 
		raise exception 'Некорректный ID сотрудника';
	end if;

	--Проверка на корректные ID имущества
	with s as (
		select unnest(_property_id) as i
	)
	, test as (
		select * from src.property_list as pl
			right join s on s.i = pl.property_id
	)
	select jsonb_agg(i) into p_check
		from test 
	where property_id is null;
	if p_check is not null then
		raise exception 'Несуществующий ID ->> %', p_check
		using hint = 'Проверьте введенный массив _property_id';
	end if;
	
	with upd as (
		update src.property_list as pl
			set employee_owner = null,
				state = 1
		where pl.property_id = any (_property_id) and pl.employee_owner = _employee_id
		returning property_id
	)
	select jsonb_agg(title) into p_property_title
		from src.v_property_list vpl
		join upd on upd.property_id = vpl.property_id;

	if p_property_title is null then
		raise exception 'Попытка открепить от сотрудника оборудование, которое за ним не было закреплено';
	end if;
	
	p_res = jsonb_build_object('Откреплено от сотрудника', p_employee_name, 'Оборудование', p_property_title);
	return p_res;

end;
$function$;
COMMENT ON FUNCTION src.take_equipment(int8, _int8) IS 'take_equipment - функция по откреплению имущества от сотрудника';


--Раздача прав пользователю
grant select on src.consignment to users;
GRANT ALL ON SCHEMA src TO users;
