/*
 * Copyright (C) 2024 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import {screen, fireEvent} from '@testing-library/react'
import userEvent, {UserEvent} from '@testing-library/user-event'
import {FAKE_FILES, FAKE_FOLDERS, FAKE_FOLDERS_AND_FILES} from '../../../../fixtures/fakeData'
import {renderComponent} from './testUtils'
import {showFlashSuccess, showFlashError} from '@canvas/alerts/react/FlashAlert'

jest.mock('@canvas/alerts/react/FlashAlert', () => ({
  showFlashSuccess: jest.fn(),
  showFlashError: jest.fn(),
}))

describe('FileFolderTable', () => {
  let flashElements: any

  beforeEach(() => {
    flashElements = document.createElement('div')
    flashElements.setAttribute('id', 'flash_screenreader_holder')
    flashElements.setAttribute('data-testid', 'flash_screenreader_holder')
    flashElements.setAttribute('role', 'alert')
    document.body.appendChild(flashElements)
  })

  afterEach(() => {
    document.body.removeChild(flashElements)
    flashElements = undefined
    jest.clearAllMocks()
  })

  it('renders filedrop when no results and not loading', async () => {
    renderComponent({rows: [], isLoading: false})

    expect(await screen.findByText('Drop files here to upload')).toBeInTheDocument()
  })

  it('renders spinner and no filedrop when loading', () => {
    renderComponent({isLoading: true})

    expect(screen.getByText('Loading data')).toBeInTheDocument()
    expect(screen.queryByText('Drop files here to upload')).not.toBeInTheDocument()
  })

  it('renders no filedrop when searching', () => {
    renderComponent({searchString: 'fileDoesNotExist'})

    const noResultsElements = screen.getAllByText('No results found')
    expect(noResultsElements.length).toBeGreaterThan(0)
    expect(screen.queryByText('Drop files here to upload')).not.toBeInTheDocument()
  })

  it('renders file drop when a file is dragged over', async () => {
    // mock file to drag over
    const file = new File(['file content'], 'example.txt', {type: 'text/plain'})
    const dataTransfer = {
      files: [file],
      items: [{kind: 'file', type: file.type}],
      types: ['Files'],
    }

    renderComponent()
    const filesTable = await screen.findByTestId('files-table')
    const filesDirectory = await screen.findByTestId('files-directory')

    filesDirectory.getBoundingClientRect = jest.fn(
      () =>
        ({
          left: 100,
          top: 100,
          right: 400,
          bottom: 400,
        }) as DOMRect,
    )

    fireEvent.dragEnter(filesTable, {dataTransfer})
    const fileUpload = await screen.findByTestId('file-upload')

    // FileDrag__dragging ensures fileDrop is visible when dragging
    expect(fileUpload).toHaveClass('FileDrag__dragging')
    expect(fileUpload).not.toHaveClass('FileDrag__full')

    // needed an event in order to correctly mock the clientX and clientY
    // simulates client leaving the file table drop area
    const event = new Event('dragleave', {
      bubbles: true,
    })
    Object.defineProperty(event, 'clientX', {value: 500})
    Object.defineProperty(event, 'clientY', {value: 500})

    filesTable.dispatchEvent(event)
    expect(fileUpload).not.toHaveClass('FileDrag__dragging')
    expect(fileUpload).not.toHaveClass('FileDrag__full')
  })

  it('renders stacked when not large', async () => {
    renderComponent({size: 'medium', rows: FAKE_FOLDERS_AND_FILES})

    expect(await screen.findAllByTestId('row-select-checkbox')).toHaveLength(
      FAKE_FOLDERS_AND_FILES.length,
    )
  })

  it('renders file/folder rows when results', async () => {
    renderComponent({rows: FAKE_FOLDERS_AND_FILES})

    expect(await screen.findAllByTestId('table-row')).toHaveLength(FAKE_FOLDERS_AND_FILES.length)
    const link = screen.getByRole('link', {
      name: `Folder ${FAKE_FOLDERS_AND_FILES[0].name}`,
    })
    expect(link).toBeInTheDocument()
  })

  it('has labels for checkboxes', async () => {
    renderComponent({rows: [FAKE_FILES[0], FAKE_FOLDERS[0]]})

    const selectAllCheckbox = screen.getByLabelText('Select all files and folders')
    expect(selectAllCheckbox).toBeInTheDocument()

    const fileCheckbox = screen.getByLabelText(`Audio File ${FAKE_FILES[0].display_name}`)
    expect(fileCheckbox).toBeInTheDocument()

    const folderCheckbox = screen.getByLabelText(`Folder ${FAKE_FOLDERS[0].name}`)
    expect(folderCheckbox).toBeInTheDocument()
  })

  describe('modified_by column', () => {
    it('renders link with user profile of file rows when modified by user', async () => {
      const {display_name, html_url} = FAKE_FILES[0].user || {}
      renderComponent({rows: [FAKE_FILES[0]]})

      const userLink = await screen.findByText(display_name!)
      expect(userLink).toBeInTheDocument()
      expect(userLink.closest('a')).toHaveAttribute('href', html_url!)
    })

    it('does not render link when folder', () => {
      renderComponent({rows: [FAKE_FOLDERS[0]]})

      const userLinks = screen.queryAllByText((_, element) => {
        if (!element) return false
        return !!element.closest('a')?.getAttribute('href')?.includes('/users/')
      })
      expect(userLinks).toHaveLength(0)
    })
  })

  describe('highlights', () => {
    let user: UserEvent
    beforeEach(() => {
      user = userEvent.setup()
      renderComponent({rows: FAKE_FOLDERS_AND_FILES})
    })

    it('no highlight by default', async () => {
      const firstRow = screen.getAllByTestId('table-row')[0]
      expect(firstRow).toHaveStyle({borderColor: ''})
    })

    it('highlight when row is hovered', async () => {
      const firstRow = screen.getAllByTestId('table-row')[0]
      await user.hover(firstRow)
      expect(firstRow).toHaveStyle({borderColor: 'brand'})
    })

    it('highlight when row is clicked', async () => {
      const firstRow = screen.getAllByTestId('table-row')[0]
      await user.click(firstRow)
      expect(firstRow).toHaveStyle({borderColor: 'brand'})
    })
  })

  describe('selection behavior', () => {
    let user: UserEvent
    let setSelectedRows: jest.Mock

    beforeEach(() => {
      user = userEvent.setup()
      setSelectedRows = jest.fn()
    })

    describe('when there is no selection', () => {
      beforeEach(() => {
        renderComponent({
          rows: [FAKE_FILES[0], FAKE_FILES[1]],
          selectedRows: new Set(),
          setSelectedRows,
        })
      })

      it('does not check any checkboxes', async () => {
        const rowCheckboxes = await screen.findAllByTestId('row-select-checkbox')
        rowCheckboxes.forEach(checkbox => expect(checkbox).not.toBeChecked())
      })

      it('does not check "Select All" checkbox', async () => {
        const selectAllCheckbox = await screen.findByTestId('select-all-checkbox')
        expect(selectAllCheckbox).not.toBeChecked()
        expect((selectAllCheckbox as HTMLInputElement).indeterminate).toBe(false)
      })

      it('calls setSelectedRows with the correct value when a row is selected', async () => {
        const rowCheckboxes = await screen.findAllByTestId('row-select-checkbox')
        await user.click(rowCheckboxes[0])
        expect(setSelectedRows).toHaveBeenCalledWith(new Set([FAKE_FILES[0].uuid]))
      })

      it('calls setSelectedRows with all values when "Select All" is clicked', async () => {
        const selectAllCheckbox = await screen.findByTestId('select-all-checkbox')
        await user.click(selectAllCheckbox)
        expect(setSelectedRows).toHaveBeenCalledWith(
          new Set([FAKE_FILES[0].uuid, FAKE_FILES[1].uuid]),
        )
      })
    })

    describe('when all rows are selected', () => {
      beforeEach(() => {
        renderComponent({
          rows: [FAKE_FILES[0], FAKE_FILES[1]],
          selectedRows: new Set([FAKE_FILES[0].uuid, FAKE_FILES[1].uuid]),
          setSelectedRows,
        })
      })

      it('checks all checkboxes', async () => {
        const rowCheckboxes = await screen.findAllByTestId('row-select-checkbox')
        rowCheckboxes.forEach(checkbox => expect(checkbox).toBeChecked())
      })

      it('checks "Select All" checkbox', async () => {
        const selectAllCheckbox = await screen.findByTestId('select-all-checkbox')
        expect(selectAllCheckbox).toBeChecked()
        expect((selectAllCheckbox as HTMLInputElement).indeterminate).toBe(false)
      })

      it('calls setSelectedRows with the correct value when a row is unselected', async () => {
        const rowCheckboxes = await screen.findAllByTestId('row-select-checkbox')
        await user.click(rowCheckboxes[0])
        expect(setSelectedRows).toHaveBeenCalledWith(new Set([FAKE_FILES[1].uuid]))
      })

      it('calls setSelectedRows with empty when "Select All" is clicked', async () => {
        const selectAllCheckbox = await screen.findByTestId('select-all-checkbox')
        await user.click(selectAllCheckbox)
        expect(setSelectedRows).toHaveBeenCalledWith(new Set())
      })
    })

    describe('when some rows are selected', () => {
      beforeEach(() => {
        renderComponent({
          rows: [FAKE_FILES[0], FAKE_FILES[1]],
          selectedRows: new Set([FAKE_FILES[0].uuid]),
          setSelectedRows,
        })
      })

      it('checks the "Select All" checkbox', async () => {
        const selectAllCheckbox = await screen.findByTestId('select-all-checkbox')
        expect(selectAllCheckbox).not.toBeChecked()
        expect((selectAllCheckbox as HTMLInputElement).indeterminate).toBe(true)
      })

      it('calls setSelectedRows with all values when "Select All" is clicked', async () => {
        const selectAllCheckbox = await screen.findByTestId('select-all-checkbox')
        await user.click(selectAllCheckbox)
        expect(setSelectedRows).toHaveBeenCalledWith(
          new Set([FAKE_FILES[0].uuid, FAKE_FILES[1].uuid]),
        )
      })

      it('updates select screen reader alert', async () => {
        const screenReader = screen.getByTestId('flash_screenreader_holder')
        expect(screenReader).toHaveTextContent('1 of 2 selected')
      })
    })
  })

  describe('rights column', () => {
    it('does not render rights column when usage rights are not required', async () => {
      renderComponent({usageRightsRequiredForContext: false, rows: [FAKE_FILES[0]]})

      expect(screen.queryByTestId('rights')).toBeNull()
    })

    it('does not render the icon if it is a folder', async () => {
      renderComponent({usageRightsRequiredForContext: true, rows: [FAKE_FOLDERS[0]]})

      const rows = await screen.findAllByTestId('table-row')
      expect(rows[0].getElementsByTagName('td')[5]).toBeEmptyDOMElement()
    })

    it('renders rights column and icons when usage rights are required', async () => {
      renderComponent({usageRightsRequiredForContext: true, rows: [FAKE_FILES[0]]})

      expect(await screen.findByTestId('rights')).toBeInTheDocument()

      const rows = await screen.findAllByTestId('table-row')
      expect(
        rows[0].getElementsByTagName('td')[5].getElementsByTagName('button')[0],
      ).toBeInTheDocument()
    })
  })

  describe('FileFolderTable - blueprint behavior', () => {
    it('renders the BP column', async () => {
      ENV.BLUEPRINT_COURSES_DATA = {
        isMasterCourse: true,
        isChildCourse: false,
        accountId: '1',
        course: {id: '1', name: 'course', enrollment_term_id: '1'},
        masterCourse: {id: '1', name: 'course', enrollment_term_id: '1'},
      }
      renderComponent()

      expect(screen.queryByText('Blueprint')).toBeInTheDocument()
    })

    it('does not render the BP column', async () => {
      ENV.BLUEPRINT_COURSES_DATA = undefined
      renderComponent()

      expect(screen.queryByText('Blueprint')).not.toBeInTheDocument()
    })
  })

  describe('FileFolderTable - delete behavior', () => {
    // TODO: the scope of this test overextends unit test
    it.skip('opens delete modal when delete button is clicked', async () => {
      const user = userEvent.setup()
      renderComponent({rows: [FAKE_FILES[0]]})

      const rowCheckboxes = await screen.findAllByTestId('row-select-checkbox')
      await user.click(rowCheckboxes[0])

      const deleteButton = screen.getByTestId('bulk-actions-delete-button')
      await user.click(deleteButton)

      expect(
        await screen.findByText('Deleting this item cannot be undone. Do you want to continue?'),
      ).toBeInTheDocument()
    })

    // TODO: the scope of this test overextends unit test
    it.skip('renders flash success when items are deleted successfully', async () => {
      const user = userEvent.setup()
      //fetchMock.delete(/.*\/folders\/46\?force=true/, 200, {overwriteRoutes: true})
      renderComponent()

      const rowCheckboxes = await screen.findAllByTestId('row-select-checkbox')
      await user.click(rowCheckboxes[0])

      const deleteButton = screen.getByTestId('bulk-actions-delete-button')
      await user.click(deleteButton)

      const confirmButton = await screen.getByTestId('modal-delete-button')
      await user.click(confirmButton)

      expect(showFlashSuccess).toHaveBeenCalledWith('1 item deleted successfully.')
    })

    // TODO: the scope of this test overextends unit test
    it.skip('renders flash error when delete fails', async () => {
      const user = userEvent.setup()
      //fetchMock.delete(/.*\/folders\/46\?force=true/, 500, {overwriteRoutes: true})
      renderComponent()

      const rowCheckboxes = await screen.findAllByTestId('row-select-checkbox')
      await user.click(rowCheckboxes[0])

      const deleteButton = screen.getByTestId('bulk-actions-delete-button')
      await user.click(deleteButton)

      const confirmButton = await screen.getByTestId('modal-delete-button')
      await user.click(confirmButton)

      expect(showFlashError).toHaveBeenCalledWith('Failed to delete items. Please try again.')
    })
  })
})
