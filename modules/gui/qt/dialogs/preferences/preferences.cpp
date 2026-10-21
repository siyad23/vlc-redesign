/*****************************************************************************
 * preferences.cpp : Preferences
 *****************************************************************************
 * Copyright (C) 2006-2007 the VideoLAN team
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Jean-Baptiste Kempf <jb@videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "dialogs/preferences/preferences.hpp"

#include "expert_view.hpp"
#include "dialogs/preferences/complete_preferences.hpp"
#include "dialogs/preferences/simple_preferences.hpp"
#include "dialogs/dialogs/dialogmodel.hpp"
#include "dialogs/dialogs_provider.hpp"
#include "widgets/native/searchlineedit.hpp"
#include "widgets/native/qvlcframe.hpp"
#include "maininterface/mainctx.hpp"
#include "style/systempalette.hpp"

#include <QHBoxLayout>
#include <QGroupBox>
#include <QRadioButton>
#include <QPushButton>
#include <QMessageBox>
#include <QDialogButtonBox>
#include <QStackedWidget>
#include <QSplitter>
#include <QShortcut>
#include <QFrame>
#include <QStyleFactory>
#include <QStyle>

#include <vlc_configuration.h>
#include <vlc_modules.h>

PrefsDialog::PrefsDialog( QWindow *parent, qt_intf_t *_p_intf )
            : QVLCDialog( parent, _p_intf )
{
    setWindowTitle( qtr( "Preferences" ) );
    setWindowRole( "vlc-preferences" );
    setWindowModality( Qt::WindowModal );
    setObjectName(QStringLiteral("preferencesDialog"));
    setWindowIcon(QIcon(QStringLiteral(":/logo/vlc256.png")));
    auto widgetStyle = QStyleFactory::create(QStringLiteral("Fusion"));
    widgetStyle->setParent(this);
    setStyle(widgetStyle);

    m_palette = new SystemPalette(this);
    m_palette->setCtx(p_intf->p_mi);
    m_palette->setSource(p_intf->p_mi ? p_intf->p_mi->getColorScheme()->currentScheme()
                                    : ColorSchemeModel::System);
    m_palette->componentComplete();
    connect(m_palette, &SystemPalette::paletteChanged, this, &PrefsDialog::updateAppearance);
    if (p_intf->p_mi)
        connect(p_intf->p_mi->getColorScheme(), &ColorSchemeModel::currentChanged, this, [this]() {
            m_palette->setSource(p_intf->p_mi->getColorScheme()->currentScheme());
        });

    /* Whether we want it or not, we need to destroy on close to get
       consistency when reset */
    setAttribute( Qt::WA_DeleteOnClose );

    p_list = NULL;

    QGridLayout *main_layout = new QGridLayout( this );
    setLayout( main_layout );

    /* View (panel) selection */
    types = new QGroupBox;
    types->setObjectName(QStringLiteral("preferencesViewModes"));
    types->setAccessibleName(qtr("Settings view"));
    types->setAlignment( Qt::AlignHCenter );
    QHBoxLayout *types_l = new QHBoxLayout;
    types_l->setSpacing( 4 );
    types_l->setContentsMargins(4, 4, 4, 4);
    simple = new QRadioButton( qtr( "Simple" ), types );
    simple->setToolTip( qtr( "Switch to simple preferences view" ) );
    all = new QRadioButton( qtr("All"), types );
    all->setToolTip( qtr( "Switch to full preferences view" ) );
    expert = new QRadioButton( qtr("Expert"), types );
    expert->setToolTip( qtr( "Switch to expert preferences view" ) );
    types_l->addWidget( simple );
    types_l->addWidget( all );
    types_l->addWidget( expert );
    types->setLayout( types_l );
    simple->setChecked( true );

    /* Buttons */
    QDialogButtonBox *buttonsBox = new QDialogButtonBox();
    QPushButton *save = new QPushButton( qtr( "&Save" ) );
    save->setObjectName(QStringLiteral("preferencesSave"));
    save->setDefault(true);
    save->setToolTip( qtr( "Save and close the dialog" ) );
    QPushButton *cancel = new QPushButton( qtr( "&Cancel" ) );
    QPushButton *reset = new QPushButton( qtr( "&Reset Preferences" ) );

    buttonsBox->addButton( save, QDialogButtonBox::AcceptRole );
    buttonsBox->addButton( cancel, QDialogButtonBox::RejectRole );
    reset->setObjectName(QStringLiteral("preferencesReset"));

    /* View (panel) stack */
    stack = new QStackedWidget();

    /* Simple view (panel) */
    simple_split_widget = new QWidget();
    simple_split_widget->setLayout( new QHBoxLayout );

    simple_tree_panel = new QWidget;
    simple_tree_panel->setObjectName(QStringLiteral("preferencesSidebar"));
    simple_tree_panel->setFixedWidth(190);
    simple_tree_panel->setLayout( new QVBoxLayout );
    simple_tree = NULL;
    simple_panels_stack = new QStackedWidget;
    for( int i = 0; i < SPrefsMax ; i++ )
        simple_panels[i] = NULL;

    simple_split_widget->layout()->addWidget( simple_tree_panel );
    simple_split_widget->layout()->addWidget( simple_panels_stack );

    simple_tree_panel->layout()->setContentsMargins(8, 12, 8, 12);
    simple_panels_stack->setContentsMargins( 12, 0, 0, 0 );
    simple_split_widget->layout()->setContentsMargins(0, 0, 0, 0);

    stack->insertWidget( SIMPLE, simple_split_widget );

    /* Advanced view (panel) */
    advanced_split_widget = new QSplitter();

    advanced_tree_panel = new QWidget;
    advanced_tree_panel->setLayout( new QVBoxLayout );
    tree_filter = NULL;
    current_filter = NULL;
    advanced_tree = NULL;
    advanced_panels_stack = new QStackedWidget;

    advanced_split_widget->addWidget( advanced_tree_panel );
    advanced_split_widget->addWidget( advanced_panels_stack );

    advanced_split_widget->setSizes(QList<int>() << 300 << 550);
    advanced_tree_panel->sizePolicy().setHorizontalStretch(1);
    advanced_panels_stack->sizePolicy().setHorizontalStretch(2);

    stack->insertWidget( ADVANCED, advanced_split_widget );

    /* Expert view (panel) */
    expert_widget = new QWidget;
    expert_widget_layout = new QGridLayout;
    expert_widget->setLayout( expert_widget_layout );

    expert_table_filter = nullptr;
    expert_table = nullptr;

    expert_text = new QLabel;
    expert_longtext = new QLabel;

    expert_text->setWordWrap(true);
    expert_longtext->setWordWrap(true);

    QFont textFont = QApplication::font();
    textFont.setPointSize( textFont.pointSize() + 2 );
    textFont.setUnderline( true );
    expert_text->setFont( textFont );

    expert_widget_layout->addWidget( expert_text, 2, 0, 1, 2 );
    expert_widget_layout->addWidget( expert_longtext, 3, 0, 1, 2 );

    stack->insertWidget( EXPERT, expert_widget );

    auto header = new QFrame;
    header->setObjectName(QStringLiteral("preferencesHeader"));
    auto headerLayout = new QHBoxLayout(header);
    headerLayout->setContentsMargins(24, 18, 24, 18);
    headerLayout->setSpacing(16);
    auto logo = new QLabel;
    logo->setAccessibleName(qtr("VLC"));
    logo->setFixedSize(48, 48);
    auto logoPixmap = QPixmap(":/logo/vlc256.png").scaled(48 * devicePixelRatioF(), 48 * devicePixelRatioF(),
                                                        Qt::KeepAspectRatio, Qt::SmoothTransformation);
    logoPixmap.setDevicePixelRatio(devicePixelRatioF());
    logo->setPixmap(logoPixmap);
    headerLayout->addWidget(logo);
    auto heading = new QVBoxLayout;
    heading->setSpacing(3);
    auto title = new QLabel(qtr("Preferences"));
    title->setObjectName(QStringLiteral("preferencesTitle"));
    auto subtitle = new QLabel(qtr("Personalize your player."));
    subtitle->setObjectName(QStringLiteral("preferencesSubtitle"));
    heading->addWidget(title);
    heading->addWidget(subtitle);
    headerLayout->addLayout(heading);
    headerLayout->addStretch();
    headerLayout->addWidget(types);

    auto footer = new QFrame;
    footer->setObjectName(QStringLiteral("preferencesFooter"));
    auto footerLayout = new QHBoxLayout(footer);
    footerLayout->setContentsMargins(24, 14, 24, 14);
    footerLayout->addWidget(reset);
    footerLayout->addStretch();
    footerLayout->addWidget(buttonsBox);

    main_layout->setContentsMargins(0, 0, 0, 0);
    main_layout->setVerticalSpacing(0);
    stack->setContentsMargins(20, 18, 20, 18);
    main_layout->addWidget(header, 0, 0);
    main_layout->addWidget(stack, 1, 0);
    main_layout->addWidget(footer, 2, 0);
    main_layout->setRowStretch(1, 1);
    updateAppearance();

    switch( var_InheritInteger( p_intf, "qt-initial-prefs-view" ) )
    {
        case 2:  setExpert();   break;
        case 1:  setAdvanced(); break;
        default: setSimple();   break;
    }

    BUTTONACT( save, &PrefsDialog::save );
    BUTTONACT( cancel, &PrefsDialog::cancel );
    BUTTONACT( reset, &PrefsDialog::reset );

    BUTTONACT( simple, &PrefsDialog::setSimple );
    BUTTONACT( all, &PrefsDialog::setAdvanced );
    BUTTONACT( expert, &PrefsDialog::setExpert );

    setMinimumSize(900, 620);
    QVLCTools::restoreWidgetPosition( p_intf, "Preferences", this, QSize( 1040, 760 ) );
}

void PrefsDialog::updateAppearance()
{
    using C = ColorContext;
    const auto color = [this](C::ColorSet set, C::ColorSection section, C::ColorName name) {
        return m_palette->getColor(set, section, name, C::Normal);
    };
    const auto window = color(C::Window, C::Bg, C::Primary);
    const auto surface = color(C::View, C::Bg, C::Primary);
    const auto text = color(C::View, C::Fg, C::Primary);
    const auto muted = color(C::View, C::Fg, C::Secondary);
    const auto border = color(C::Window, C::Decoration, C::Border);
    const auto field = color(C::TextField, C::Bg, C::Primary);
    const auto accent = m_palette->get_orange500();
    const auto accentText = color(C::ButtonAccent, C::Fg, C::Primary);
    auto selected = accent;
    selected.setAlpha(28);

    QPalette palette = qApp->palette();
    palette.setColor(QPalette::Window, window);
    palette.setColor(QPalette::WindowText, text);
    palette.setColor(QPalette::Base, field);
    palette.setColor(QPalette::AlternateBase, surface);
    palette.setColor(QPalette::Text, text);
    palette.setColor(QPalette::Button, surface);
    palette.setColor(QPalette::ButtonText, text);
    palette.setColor(QPalette::Highlight, accent);
    palette.setColor(QPalette::HighlightedText, accentText);
    palette.setColor(QPalette::Link, accent);
    palette.setColor(QPalette::PlaceholderText, muted);
    const auto disabled = m_palette->getColor(C::View, C::Fg, C::Primary, C::Disabled);
    palette.setColor(QPalette::Disabled, QPalette::WindowText, disabled);
    palette.setColor(QPalette::Disabled, QPalette::Text, disabled);
    palette.setColor(QPalette::Disabled, QPalette::ButtonText, disabled);
    setPalette(palette);

    // Scope widget styling to this dialog; the main player uses the same palette in QML.
    setStyleSheet(QStringLiteral(R"(
        QDialog#preferencesDialog { background: %1; }
        QLabel { background: transparent; }
        QLabel#preferencesTitle { font-size: 23px; font-weight: 600; }
        QLabel#preferencesSubtitle { color: %4; font-size: 12px; }
        QFrame#preferencesHeader { border-bottom: 1px solid %5; }
        QFrame#preferencesFooter { border-top: 1px solid %5; }
        QWidget#preferencesSidebar { background: %2; border-radius: 10px; }
        QGroupBox { background: %2; border: 1px solid %5; border-radius: 8px;
                    margin-top: 18px; padding: 14px 12px 10px 12px; }
        QGroupBox::title { subcontrol-origin: margin; left: 12px; padding: 0 4px; color: %4; }
        QGroupBox#preferencesViewModes { background: %6; border: 1px solid %5;
                                        margin: 0; padding: 0; border-radius: 8px; }
        QGroupBox#preferencesViewModes QRadioButton { padding: 7px 12px; border-radius: 5px; }
        QGroupBox#preferencesViewModes QRadioButton::indicator { width: 0; height: 0; }
        QGroupBox#preferencesViewModes QRadioButton:checked { background: %9; color: %7; }
        QPushButton { background: %2; border: 1px solid %5; border-radius: 6px; padding: 8px 16px; }
        QPushButton:hover { border-color: %7; }
        QPushButton:focus, QToolButton:focus, QRadioButton:focus { border: 1px solid %7; }
        QPushButton#preferencesSave { background: %7; color: %8; border-color: %7; font-weight: 600; }
        QPushButton#preferencesSave:hover { background: %10; }
        QPushButton#preferencesReset { border-color: transparent; color: %4; background: transparent; }
        QPushButton#folderAction { padding: 0; font-size: 18px; background: transparent; border-color: transparent; }
        QPushButton#folderAction:hover { background: %9; border-color: %7; }
        QPushButton#folderAction:focus { border-color: %7; }
        QPushButton#preferenceCategory { background: transparent; border: 1px solid transparent;
                                        text-align: left; padding: 10px 12px; border-radius: 7px; }
        QPushButton#preferenceCategory:hover { background: %6; }
        QPushButton#preferenceCategory:checked { background: %9; color: %7; }
        QPushButton#preferenceCategory:focus { border-color: %7; }
        QLineEdit, QComboBox, QAbstractSpinBox, QTextEdit, QPlainTextEdit {
            background: %6; border: 1px solid %5; border-radius: 5px; padding: 6px; selection-background-color: %7; }
        QLineEdit:focus, QComboBox:focus, QAbstractSpinBox:focus { border-color: %7; }
        QAbstractSpinBox QLineEdit { border: none; padding: 0; background: transparent; }
        QComboBox::drop-down { border: none; width: 22px; }
        QTreeView, QTableView, QListView { background: %2; border: 1px solid %5; border-radius: 7px;
                                        selection-background-color: %9; selection-color: %3; }
        QTreeView::item, QListView::item { padding: 6px 4px; }
        QHeaderView::section { background: %6; border: none; border-bottom: 1px solid %5; padding: 8px; }
        QScrollArea { border: none; background: transparent; }
        QScrollBar:vertical { background: transparent; width: 10px; margin: 0; }
        QScrollBar::handle:vertical { background: %5; border-radius: 4px; min-height: 30px; margin: 1px; }
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
        QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical { background: transparent; }
        QSplitter::handle { background: %5; width: 1px; }
        QToolTip { background: %6; color: %3; border: 1px solid %5; padding: 5px; }
    )").arg(window.name(QColor::HexArgb), surface.name(QColor::HexArgb), text.name(QColor::HexArgb),
            muted.name(QColor::HexArgb), border.name(QColor::HexArgb), field.name(QColor::HexArgb),
            accent.name(), accentText.name(QColor::HexArgb), selected.name(QColor::HexArgb)).arg(accent.lighter(110).name()));

    for (auto categories : findChildren<SPrefsCatList*>())
        categories->updateIcons();
    for (auto panel : findChildren<SPrefsPanel*>())
        panel->updateLayoutPreviews();
}

PrefsDialog::~PrefsDialog()
{
    module_list_free( p_list );
}

void PrefsDialog::setExpert()
{
    /* Lazy creation */
    if( !expert_table )
    {
        if ( !p_list )
            p_list = module_list_get( &count );

        expert_table_filter = new SearchLineEdit( expert_widget );
        expert_table_filter->setMinimumHeight( 26 );
        expert_table_filter_modified = new QCheckBox( qtr( "Modified only" ), expert_widget );

        QShortcut *search = new QShortcut( QKeySequence( QKeySequence::Find ), expert_table_filter );

        ExpertPrefsTableModel *table_model = new ExpertPrefsTableModel( p_list, count, this );
        expert_table = new ExpertPrefsTable( expert_widget );
        expert_table->setModel( table_model );
        expert_table->resizeColumnToContents( ExpertPrefsTableModel::NameField );

        expert_widget_layout->addWidget( expert_table_filter, 0, 0 );
        expert_widget_layout->addWidget( expert_table_filter_modified, 0, 1 );
        expert_widget_layout->addWidget( expert_table, 1, 0, 1, 2 );

        connect( expert_table->selectionModel(), &QItemSelectionModel::currentChanged,
                 this, &PrefsDialog::changeExpertDesc );
        connect( expert_table_filter, &SearchLineEdit::textChanged,
                 this, &PrefsDialog::expertTableFilterChanged );
        connect( expert_table_filter_modified, &QCheckBox::toggled,
                 this, &PrefsDialog::expertTableFilterModifiedToggled );
        connect( search, &QShortcut::activated,
                 expert_table_filter, QOverload<>::of(&SearchLineEdit::setFocus) );

        /* Set initial selection */
        expert_table->setCurrentIndex(
                expert_table->model()->index( 0, 0, QModelIndex() ) );
    }

    expert->setChecked( true );
    stack->setCurrentIndex( EXPERT );
    setWindowTitle( qtr( "Expert Preferences" ) );
}

void PrefsDialog::setAdvanced()
{
    /* Lazy creation */
    if( !advanced_tree )
    {
        if ( !p_list )
            p_list = module_list_get( &count );

        advanced_tree = new PrefsTree( p_intf, advanced_tree_panel, p_list, count );

        tree_filter = new SearchLineEdit( advanced_tree_panel );
        tree_filter->setMinimumHeight( 26 );

        current_filter = new QCheckBox( qtr("Only show current") );
        current_filter->setToolTip(
                    qtr("Only show modules related to current playback") );

        QShortcut *search = new QShortcut( QKeySequence( QKeySequence::Find ), tree_filter );

        advanced_tree_panel->layout()->addWidget( tree_filter );
        advanced_tree_panel->layout()->addWidget( current_filter );
        advanced_tree_panel->layout()->addWidget( advanced_tree );
        advanced_tree_panel->setSizePolicy( QSizePolicy::Maximum, QSizePolicy::Preferred );

        connect( advanced_tree, &PrefsTree::currentItemChanged, this, &PrefsDialog::changeAdvPanel );
        connect( tree_filter, &SearchLineEdit::textChanged, this, &PrefsDialog::advancedTreeFilterChanged );
        connect( current_filter, &QtCheckboxChanged, this, &PrefsDialog::onlyLoadedToggled );
        connect( search, &QShortcut::activated, tree_filter, QOverload<>::of(&SearchLineEdit::setFocus) );

        /* Set initial selection */
        advanced_tree->setCurrentIndex(
                advanced_tree->model()->index( 0, 0, QModelIndex() ) );
    }

    all->setChecked( true );
    stack->setCurrentIndex( ADVANCED );
    setWindowTitle( qtr( "Advanced Preferences" ) );
}

void PrefsDialog::setSimple()
{
    /* If no simple_tree, create one, connect it */
    if( !simple_tree )
    {
        simple_tree = new SPrefsCatList( p_intf, simple_tree_panel );
        connect( simple_tree, &SPrefsCatList::currentItemChanged,
                 this, &PrefsDialog::changeSimplePanel );
        simple_tree_panel->layout()->addWidget( simple_tree );
        simple_tree_panel->setSizePolicy( QSizePolicy::Fixed, QSizePolicy::Preferred );
    }

    if( ! simple_panels[SPrefsDefaultCat] )
        changeSimplePanel( SPrefsDefaultCat );

    simple->setChecked( true );
    stack->setCurrentIndex( SIMPLE );
    setWindowTitle( qtr( "Simple Preferences" ) );
}

/* Switching from on simple panel to another */
void PrefsDialog::changeSimplePanel( int number )
{
    if( ! simple_panels[number] )
    {
        SPrefsPanel *insert = new SPrefsPanel( p_intf, simple_panels_stack, number ) ;
        simple_panels_stack->insertWidget( number, insert );
        simple_panels[number] = insert;
    }
    simple_panels_stack->setCurrentWidget( simple_panels[number] );
}

/* Changing from one Advanced Panel to another */
void PrefsDialog::changeAdvPanel( QTreeWidgetItem *item )
{
    if( item == NULL ) return;
    PrefsTreeItem *node = static_cast<PrefsTreeItem *>( item );

    if( !node->panel )
    {
        node->panel = new AdvPrefsPanel( p_intf, advanced_panels_stack, node );
        advanced_panels_stack->addWidget( node->panel );
    }
    advanced_panels_stack->setCurrentWidget( node->panel );
}

/* Changing from one Expert item description to another */
void PrefsDialog::changeExpertDesc( const QModelIndex &current, const QModelIndex &previous )
{
    Q_UNUSED( previous );
    if( !current.isValid() )
       return;
    ExpertPrefsTableItem *item = expert_table->myModel()->itemAt( current );

    expert_text->setText( item->getTitle() );
    expert_longtext->setText( item->getDescription() );
}

/* Actual apply and save for the preferences */
void PrefsDialog::save()
{
    if( simple->isChecked() && simple_tree->isVisible() )
    {
        msg_Dbg( p_intf, "Saving the simple preferences" );
        for( int i = 0 ; i< SPrefsMax; i++ ){
            if( simple_panels_stack->widget(i) )
                qobject_cast<SPrefsPanel *>(simple_panels_stack->widget(i))->apply();
        }
    }
    else if( all->isChecked() && advanced_tree->isVisible() )
    {
        msg_Dbg( p_intf, "Saving the advanced preferences" );
        advanced_tree->applyAll();
    }
    else if( expert->isChecked() && expert_table->isVisible() )
    {
        msg_Dbg( p_intf, "Saving the expert preferences" );
        expert_table->applyAll();
    }

    /* Save to file */
    if( config_SaveConfigFile( p_intf ) != 0 )
    {
        DialogErrorModel::getInstance(p_intf)->pushError(
            qtr( "Cannot save Configuration" ),
            qtr("Preferences file could not be saved")
        );
        if (p_intf->b_isDialogProvider)
        {
            //at this point we are closing the preference dialog which is modal,
            //we need to postpone the dialog raising up
            QMetaObject::invokeMethod(DialogsProvider::getInstance(), [](){
                DialogsProvider::getInstance()->messagesDialog(1);
            }, Qt::QueuedConnection);
        }
    }

    if( p_intf->p_mi )
        p_intf->p_mi->reloadPrefs();
    accept();

    // Don't save widget position if reset is pending
    if( !p_intf->preferencesResetPending )
        QVLCTools::saveWidgetPosition( p_intf, "Preferences", this );

    if( p_intf->preferencesResetPending )
    {
        int restart = QMessageBox::question(
                          this,
                          qtr( "Restart Required" ),
                          qtr( "VLC needs to be restarted for the reset to take full effect.\n\nRestart now?" ),
                          QMessageBox::Yes | QMessageBox::No,
                          QMessageBox::Yes);
        
        if( restart == QMessageBox::Yes )
        {
            // Quit VLC
            emit p_intf->p_mi->askToQuit();
        }
        else
        {
            // User chose not to restart - clear the flag
            p_intf->preferencesResetPending = false;
        }
    }

}

/* Clean the preferences, dunno if it does something really */
void PrefsDialog::cancel()
{
    bool wasResetting = p_intf->preferencesResetPending;
    
    // Clear the reset flag
    p_intf->preferencesResetPending = false;
    
    if( !wasResetting )
        QVLCTools::saveWidgetPosition( p_intf, "Preferences", this );
    reject();
}

/* Reset all the preferences, when you click the button */
void PrefsDialog::reset()
{
    int ret = QMessageBox::question(
                 this,
                 qtr( "Reset Preferences" ),
                 qtr( "Are you sure you want to reset your VLC media player preferences?" ),
                 QMessageBox::Ok | QMessageBox::Cancel,
                 QMessageBox::Ok);

    if( ret == QMessageBox::Ok )
    {
        config_ResetAll();
        config_SaveConfigFile( p_intf );
        getSettings()->clear();
        p_intf->preferencesResetPending = true;
        p_intf->p_mi->reloadPrefs();
        p_intf->p_mi->reloadFromSettings();

#ifdef _WIN32
        simple_panels[0]->cleanLang();
#endif

    }
}

void PrefsDialog::expertTableFilterModifiedToggled( bool checked )
{
    expert_table->filter( expert_table_filter->text(), checked );
}

void PrefsDialog::expertTableFilterChanged( const QString & text )
{
    expert_table->filter( text, expert_table_filter_modified->isChecked() );
}

void PrefsDialog::advancedTreeFilterChanged( const QString & text )
{
    advanced_tree->filter( text );
}

void PrefsDialog::onlyLoadedToggled()
{
    advanced_tree->setLoadedOnly( current_filter->isChecked() );
}
